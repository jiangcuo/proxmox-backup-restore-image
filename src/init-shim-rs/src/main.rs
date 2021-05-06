use anyhow::{bail, Error};
use std::ffi::CStr;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

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

    if let Err(err) = run_agetty() {
        // not fatal
        println!("[init-shim] debug: agetty start failed: {}", err);
    }

    let uptime = read_uptime();
    println!("[init-shim] reached daemon start after {:.2}s", uptime);

    do_run("/proxmox-restore-daemon");
}

fn run_agetty() -> Result<(), Error> {
    use nix::unistd::{fork, ForkResult};

    if !PathBuf::from("/sbin/agetty").exists() {
        bail!("/sbin/agetty not found, probably not running debug mode and safe to ignore");
    }

    if !PathBuf::from("/sys/class/tty/ttyS1/device/driver/serial8250").exists() {
        bail!("ttyS1 device does not exist or is not a 8250");
    }

    let dev = fs::read_to_string("/sys/class/tty/ttyS1/dev")?;
    let (tty_maj, tty_min) = dev.trim().split_at(dev.find(':').unwrap_or(1));
    do_mknod("/dev/ttyS1", tty_maj.parse()?, tty_min[1..].parse()?)?;

    match unsafe { fork() } {
        Ok(ForkResult::Parent { .. }) => {}
        Ok(ForkResult::Child) => loop {
            // continue to restart agetty if it exits, this runs in a forked process
            println!("[init-shim] Spawning new agetty");
            let res = Command::new("/sbin/agetty")
                .args(&["-a", "root", "-l", "/bin/busybox", "-o", "sh", "115200", "ttyS1"])
                .spawn()
                .unwrap()
                .wait()
                .unwrap();
            println!("[init-shim] agetty exited: {}", res.code().unwrap_or(-1));
        },
        Err(err) => println!("fork failed: {}", err),
    }

    Ok(())
}

fn do_mount(target: &str, fstype: &str) -> Result<(), Error> {
    use nix::mount::{mount, MsFlags};
    fs::create_dir_all(target)?;
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
