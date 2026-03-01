use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode};
use reqwest::Client;
use serde::Deserialize;
use std::error::Error;
use std::fs;

#[derive(Debug, Deserialize)]
pub struct UserToken {
    pub iat: usize,
    pub exp: usize,
    pub uuid: String,
    #[serde(rename = "tokenHash")]
    pub token_hash: String,
}

pub fn decode_user_token(token: &str) -> Result<UserToken, Box<dyn Error>> {
    let public_key_pem = fs::read("public.pem")?;
    let decoding_key = DecodingKey::from_ed_pem(&public_key_pem)?;

    let mut validation = Validation::new(Algorithm::EdDSA);
    validation.validate_exp = true;

    let token_data: UserToken = decode::<UserToken>(token, &decoding_key, &validation)?.claims;

    Ok(token_data)
}

#[derive(serde::Deserialize)]
struct ApiResponse {
    data: UserData,
}

#[derive(serde::Deserialize)]
struct UserData {
    roles: Vec<String>,
}

pub async fn get_user_roles(host: &str, uuid: &str) -> Result<Vec<String>, Box<dyn Error>> {
    let url = format!("{}/users/{}", host, uuid);

    let client = Client::new();

    let response: ApiResponse = client.get(&url).send().await?.json().await?;

    let lower_roles: Vec<String> = response
        .data
        .roles
        .into_iter()
        .map(|role| role.to_lowercase())
        .collect();
    return Ok(lower_roles);
}
