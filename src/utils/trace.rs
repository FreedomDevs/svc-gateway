use rand::Rng;

pub fn generate_trace_id() -> String {
    let mut rng = rand::thread_rng();
    let bytes: [u8; 8] = rng.r#gen();
    hex::encode(bytes)
}
