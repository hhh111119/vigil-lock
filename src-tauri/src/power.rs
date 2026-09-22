use std::process::{Child, Command, Stdio};

/// Owns a `caffeinate` child so idle display + system sleep stay off.
/// `-w <pid>` ties the assertion to this app: if Vigil dies, caffeinate exits.
pub struct CaffeinateGuard {
    child: Child,
}

impl CaffeinateGuard {
    pub fn start() -> Result<Self, String> {
        let pid = std::process::id().to_string();
        let child = Command::new("/usr/bin/caffeinate")
            .args(["-di", "-w", &pid])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("无法启动 caffeinate：{e}"))?;
        Ok(Self { child })
    }
}

impl Drop for CaffeinateGuard {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
