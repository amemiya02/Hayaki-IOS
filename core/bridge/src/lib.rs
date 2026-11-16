// Copyright: Hayaki contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! C bridge between Hayaki and Anki's Rust core. The interface is declared in
//! `include/HayakiBridge.h`. Every entry point catches panics, so a panic in
//! the core becomes an error for the caller instead of aborting the app.

use std::panic::catch_unwind;
use std::panic::AssertUnwindSafe;
use std::ptr;
use std::slice;

use anki::backend::init_backend;
use anki::backend::Backend;
use anki_proto::backend::backend_error::Kind;
use anki_proto::backend::BackendError;
use prost::Message;

/// Opaque handle given to C callers.
pub struct HayakiBackend(Backend);

#[repr(C)]
pub struct HayakiBuffer {
    data: *mut u8,
    len: usize,
}

impl HayakiBuffer {
    fn empty() -> Self {
        HayakiBuffer {
            data: ptr::null_mut(),
            len: 0,
        }
    }

    fn from_vec(bytes: Vec<u8>) -> Self {
        if bytes.is_empty() {
            return Self::empty();
        }
        let boxed = bytes.into_boxed_slice();
        let len = boxed.len();
        let data = Box::into_raw(boxed) as *mut u8;
        HayakiBuffer { data, len }
    }
}

fn encoded_error(kind: Kind, message: String) -> Vec<u8> {
    BackendError {
        message,
        kind: kind as i32,
        ..Default::default()
    }
    .encode_to_vec()
}

fn panic_message(payload: &(dyn std::any::Any + Send)) -> String {
    let detail = if let Some(text) = payload.downcast_ref::<&str>() {
        (*text).to_string()
    } else if let Some(text) = payload.downcast_ref::<String>() {
        text.clone()
    } else {
        "unknown panic payload".to_string()
    };
    format!("The Anki core panicked: {detail}")
}

/// # Safety
/// `ptr` must be null with `len == 0`, or point to `len` readable bytes.
unsafe fn input_slice<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if ptr.is_null() || len == 0 {
        &[]
    } else {
        slice::from_raw_parts(ptr, len)
    }
}

/// # Safety
/// See `HayakiBridge.h`. `error` must point to writable memory.
#[no_mangle]
pub unsafe extern "C" fn hayaki_backend_open(
    init: *const u8,
    init_len: usize,
    error: *mut HayakiBuffer,
) -> *mut HayakiBackend {
    let init = input_slice(init, init_len);
    let result = catch_unwind(|| init_backend(init));
    let failure = match result {
        Ok(Ok(backend)) => {
            *error = HayakiBuffer::empty();
            return Box::into_raw(Box::new(HayakiBackend(backend)));
        }
        Ok(Err(message)) => encoded_error(Kind::InvalidInput, message),
        Err(payload) => encoded_error(Kind::AnkidroidPanicError, panic_message(&*payload)),
    };
    *error = HayakiBuffer::from_vec(failure);
    ptr::null_mut()
}

/// # Safety
/// See `HayakiBridge.h`. `backend` must come from `hayaki_backend_open` and not
/// be closed; `output` must point to writable memory.
#[no_mangle]
pub unsafe extern "C" fn hayaki_backend_run(
    backend: *mut HayakiBackend,
    service: u32,
    method: u32,
    input: *const u8,
    input_len: usize,
    output: *mut HayakiBuffer,
) -> i32 {
    let backend = &(*backend).0;
    let input = input_slice(input, input_len);
    let result = catch_unwind(AssertUnwindSafe(|| {
        backend.run_service_method(service, method, input)
    }));
    let (status, bytes) = match result {
        Ok(Ok(response)) => (0, response),
        Ok(Err(error)) => (1, error),
        Err(payload) => (
            1,
            encoded_error(Kind::AnkidroidPanicError, panic_message(&*payload)),
        ),
    };
    *output = HayakiBuffer::from_vec(bytes);
    status
}

/// # Safety
/// `buffer` must have been returned by this bridge and not freed before.
#[no_mangle]
pub unsafe extern "C" fn hayaki_buffer_free(buffer: HayakiBuffer) {
    if buffer.data.is_null() {
        return;
    }
    let slice = ptr::slice_from_raw_parts_mut(buffer.data, buffer.len);
    drop(Box::from_raw(slice));
}

/// # Safety
/// `backend` must be null or come from `hayaki_backend_open` and not be closed.
#[no_mangle]
pub unsafe extern "C" fn hayaki_backend_close(backend: *mut HayakiBackend) {
    if backend.is_null() {
        return;
    }
    let backend = Box::from_raw(backend);
    // A panic while dropping must not unwind into C.
    let _ = catch_unwind(AssertUnwindSafe(move || drop(backend)));
}
