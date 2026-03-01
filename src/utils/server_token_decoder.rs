use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use sha2::{Digest, Sha256};
use std::collections::HashSet;

pub fn decode_server_token(allowed_server_tokens: &HashSet<String>, token: &str) -> Option<String> {
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    let token_hash = hex::encode(hasher.finalize());

    if !allowed_server_tokens.contains(&token_hash) {
        return None;
    }

    let decoded_bytes = BASE64.decode(token).ok()?;
    let colon_pos = decoded_bytes.iter().position(|&b| b == b':')?;
    let server_name = std::str::from_utf8(&decoded_bytes[..colon_pos])
        .ok()?
        .to_string();

    return Some(server_name);
}
