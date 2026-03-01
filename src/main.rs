mod config;

use axum::{
    Router,
    body::{Body, Bytes, to_bytes},
    extract::{Request, State},
    http::{Response, StatusCode},
};
use config::loader::load_config;
use reqwest::Client;
use std::sync::Arc;

use axum::http::Method as AxumMethod;
use reqwest::Method as ReqwestMethod;
use std::str::FromStr;

use crate::config::RouteConfig;

#[tokio::main]
async fn main() {
    let shared_config = Arc::new(load_config("config.yaml"));

    println!("Loaded config: {:#?}", &shared_config);

    let app = Router::new()
        .fallback(handler)
        .with_state(shared_config.clone());

    let listener = tokio::net::TcpListener::bind(&shared_config.gateway.host)
        .await
        .unwrap();
    axum::serve(listener, app).await.unwrap();
}

// GPT код
fn match_route(pattern: &str, path: &str) -> Option<Vec<(String, String)>> {
    let pattern_parts: Vec<&str> = pattern.trim_matches('/').split('/').collect();
    let path_parts: Vec<&str> = path.trim_matches('/').split('/').collect();

    if pattern_parts.len() != path_parts.len() {
        return None;
    }

    let mut params = Vec::new();

    for (p, v) in pattern_parts.iter().zip(path_parts.iter()) {
        if p.starts_with(':') {
            params.push((p[1..].to_string(), v.to_string()));
        } else if p != v {
            return None;
        }
    }

    Some(params)
}

async fn handler(
    State(config): State<Arc<config::GatewayConfig>>,
    req: Request,
) -> Result<Response<Body>, StatusCode> {
    let request_path = req.uri().path();
    let method: &AxumMethod = req.method();
    let mut service_url: Option<String> = None;
    let mut matched_route: Option<RouteConfig> = None;

    'outer: for (_, service) in &config.services {
        for route in &service.routes {
            if match_route(&route.path, request_path).is_some() && route.method == method.as_str() {
                service_url = Some(service.base_url.clone());
                matched_route = Some(route.clone());
                break 'outer;
            }
        }
    }

    if service_url.is_none() {
        return Ok(Response::builder().status(404).body(Body::empty()).unwrap());
    }

    let service_url = format!(
        "{}{}",
        service_url.unwrap(),
        req.uri().path_and_query().unwrap()
    );

    let client = Client::new();

    let reqwest_method = ReqwestMethod::from_str(req.method().as_str()).map_err(|e| {
        eprintln!("Failed to parse method: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let body_bytes: Bytes = to_bytes(req.into_body(), config.gateway.max_body_size)
        .await
        .map_err(|e| {
            eprintln!("Failed to read request body: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let resp = client
        .request(reqwest_method, &service_url)
        .body(body_bytes)
        .send()
        .await
        .map_err(|_| StatusCode::BAD_GATEWAY)?;

    // Преобразуем ответ в axum::Response
    let status = StatusCode::from_u16(resp.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
    let bytes = resp.bytes().await.map_err(|_| StatusCode::BAD_GATEWAY)?;
    let response = Response::builder()
        .status(status)
        .body(Body::from(bytes))
        .unwrap();

    Ok(response)
}
