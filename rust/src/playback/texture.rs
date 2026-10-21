use std::sync::Arc;

use irondash_texture::{
    BoxedPixelData, PayloadProvider, PixelData, PixelDataProvider, SimplePixelData,
};
use parking_lot::Mutex;

/// The latest preview frame, read by the platform texture when Flutter
/// draws.
#[derive(Default)]
pub struct LatestFrame(Mutex<Option<Frame>>);

/// Tightly packed RGBA pixels with their width and height.
type Frame = (Arc<Vec<u8>>, u32, u32);

struct SharedPixels {
    data: Arc<Vec<u8>>,
    width: u32,
    height: u32,
}

impl PixelDataProvider for SharedPixels {
    fn get(&self) -> PixelData<'_> {
        PixelData {
            width: self.width as i32,
            height: self.height as i32,
            data: &self.data,
        }
    }
}

impl PayloadProvider<BoxedPixelData> for LatestFrame {
    fn get_payload(&self) -> BoxedPixelData {
        match self.0.lock().clone() {
            Some((data, width, height)) => Box::new(SharedPixels {
                data,
                width,
                height,
            }),
            None => SimplePixelData::new_boxed(2, 2, vec![0; 16]),
        }
    }
}

impl LatestFrame {
    pub fn set(&self, data: Arc<Vec<u8>>, width: u32, height: u32) {
        *self.0.lock() = Some((data, width, height));
    }
}
