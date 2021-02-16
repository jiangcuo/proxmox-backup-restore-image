use anyhow::Error;
use std::ffi::CStr;
use std::fs;

const URANDOM_MAJ: u64 = 1;
const URANDOM_MIN: u64 = 9;

/// Set up a somewhat normal linux userspace environment before starting the restore daemon, and
/// provide error messages to the user if doing so fails.
///
/// This is supposed to run as /init in an initramfs image.
fn main() {
    println!("[init-shim] beginning user space setup");

    // /dev is mounted automatically
    wrap_err("mount /sys", || do_mount("/sys", "sysfs"));
    wrap_err("mount /proc", || do_mount("/proc", "proc"));

    // make device nodes required by daemon
    wrap_err("mknod /dev/urandom", || {
        do_mknod("/dev/urandom", URANDOM_MAJ, URANDOM_MIN)
    });

    let uptime = read_uptime();
    println!("[init-shim] reached daemon start after {:.2}s", uptime);

    do_run("/proxmox-restore-daemon");
}

fn do_mount(target: &str, fstype: &str) -> Result<(), Error> {
    use nix::mount::{mount, MsFlags};
    fs::create_dir(target)?;
    let none_type: Option<&CStr> = None;
    mount(
        none_type,
        target,
        Some(fstype),
        MsFlags::MS_NOSUID | MsFlags::MS_NOEXEC,
        none_type,
    )?;
    Ok(())
}

fn do_mknod(path: &str, maj: u64, min: u64) -> Result<(), Error> {
    use nix::sys::stat;
    let dev = stat::makedev(maj, min);
    stat::mknod(path, stat::SFlag::S_IFCHR, stat::Mode::S_IRWXU, dev)?;
    Ok(())
}

fn read_uptime() -> f32 {
    let uptime = wrap_err("read /proc/uptime", || {
        fs::read_to_string("/proc/uptime").map_err(|e| e.into())
    });
    // this can never fail on a sane kernel, so just unwrap
    uptime
        .split_ascii_whitespace()
        .next()
        .unwrap()
        .parse()
        .unwrap()
}

fn do_run(cmd: &str) -> ! {
    use std::io::ErrorKind;
    use std::process::Command;

    let spawn_res = Command::new(cmd).env("RUST_BACKTRACE", "1").spawn();

    match spawn_res {
        Ok(mut child) => {
            let res = wrap_err("wait failed", || child.wait().map_err(|e| e.into()));
            error(&format!(
                "child process {} (pid={} exitcode={}) exited unexpectedly, check log for more info",
                cmd,
                child.id(),
                res.code().unwrap_or(-1),
            ));
        }
        Err(err) if err.kind() == ErrorKind::NotFound => {
            error(&format!(
                concat!(
                    "{} missing from image.\n",
                    "This initramfs should only be run with proxmox-file-restore!"
                ),
                cmd
            ));
        }
        Err(err) => {
            error(&format!(
                "unexpected error during start of {}: {}",
                cmd, err
            ));
        }
    }
}

fn wrap_err<R, F: FnOnce() -> Result<R, Error>>(op: &str, f: F) -> R {
    match f() {
        Ok(r) => r,
        Err(e) => error(&format!("operation '{}' failed: {}", op, e)),
    }
}

fn error(msg: &str) -> ! {
    use nix::sys::reboot;

    println!("\n--------");
    println!("ERROR: Init shim failed\n");
    println!("{}", msg);
    println!("--------\n");

    // in case a fatal error occurs we shut down the VM, there's no sense in continuing and this
    // will certainly alert whoever started us up in the first place
    let err = reboot::reboot(reboot::RebootMode::RB_POWER_OFF).unwrap_err();
    println!("'reboot' syscall failed: {} - cannot continue", err);

    // in case 'reboot' fails just loop forever
    loop {
        std::thread::sleep(std::time::Duration::from_secs(600));
    }
}
