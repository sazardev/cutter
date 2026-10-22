//! What only Android needs: FFmpeg's MediaCodec encoder reaches the Java
//! side through JNI, so it has to be told which `JavaVM` it runs in.

use std::ffi::c_void;

extern "C" {
    /// From FFmpeg's `libavcodec/jni.h`, which the generated bindings do not
    /// include; built in by `--enable-jni`.
    fn av_jni_set_java_vm(vm: *mut c_void, log_ctx: *mut c_void) -> i32;
}

/// Gives FFmpeg the `JavaVM`, which `irondash_engine_context` already holds
/// (it owns the library's `JNI_OnLoad`).
pub fn init() {
    match irondash_engine_context::EngineContext::get_java_vm() {
        Ok(vm) => {
            // SAFETY: the pointer is the process's JavaVM, valid for its life.
            unsafe { av_jni_set_java_vm(vm.get_java_vm_pointer().cast(), std::ptr::null_mut()) };
        }
        Err(e) => crate::diagnostics::warn(format!("no JavaVM for FFmpeg: {e}")),
    }
}
