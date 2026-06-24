mod config;
mod subscribe;
mod utils;

use axum::{
    Router,
    body::{Body, Bytes, to_bytes},
    extract::{Request, State},
    http::{
        HeaderMap as AxumHeaderMap, HeaderName as AxumHeaderName, HeaderValue as AxumHeaderValue,
        Response, StatusCode,
    },
    response::IntoResponse,
};
use reqwest::{
    Client,
    header::{HeaderMap, HeaderName, HeaderValue},
};
use std::sync::Arc;
use tokio::{
    signal::unix::{SignalKind, signal},
    sync::{RwLock, broadcast},
};

use axum::http::Method as AxumMethod;
use reqwest::Method as ReqwestMethod;
use std::str::FromStr;

use crate::{
    config::{RouteConfig, loader::load_config},
    subscribe::app_event::AppEvent,
    utils::generate_auth_headers::generate_auth_headers,
};

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<RwLock<config::GatewayConfig>>,
    pub event_tx: broadcast::Sender<AppEvent>,
}

//#[tokio::main]
async fn main() {
    let appstate: AppState;

    appstate.config = Arc::new(RwLock::new(load_config("config.yaml")));
    println!("Config loaded: {:#?}", appstate.config.read().await);

    let events_broadcast: broadcast::Sender<AppEvent>;

    let app = Router::new()
        // .route("/subscribe", subscribe_handler)
        .fallback(handler)
        .with_state(appstate);

    let shared_config_clone = appstate.config.clone();
    tokio::spawn(async move {
        let mut sighup = signal(SignalKind::hangup()).unwrap();
        while sighup.recv().await.is_some() {
            println!("Reloading config...");
            let new_config = load_config("config.yaml");
            let mut cfg = shared_config_clone.write().await;
            *cfg = new_config;
            println!("Config reloaded: {:#?}", &*cfg);
        }
    });

    let listener = tokio::net::TcpListener::bind(&appstate.config.read().await.gateway.host)
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
    State(state): State<AppState>,
    req: Request,
) -> Result<Response<Body>, StatusCode> {
    let cfg = state.config.read().await;

    let request_path = req.uri().path();
    let method: &AxumMethod = req.method();
    let mut service_url: Option<String> = None;
    let mut matched_route: Option<RouteConfig> = None;

    'outer: for (_, service) in &cfg.services {
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

    let service_url: String = service_url.unwrap();
    let matched_route: RouteConfig = matched_route.unwrap();

    let auth_reqwest_headers = match generate_auth_headers(&req, &matched_route, &cfg).await {
        Err(err) => return Ok(err),
        Ok(result) => result,
    };

    let service_url = format!("{}{}", service_url, req.uri().path_and_query().unwrap());

    let client = Client::new();

    let reqwest_method = ReqwestMethod::from_str(req.method().as_str()).map_err(|e| {
        eprintln!("Failed to parse method: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let mut client_reqwest_headers = HeaderMap::new();
    if let Some(content_type) = &req.headers().get("content-type") {
        client_reqwest_headers.insert(
            HeaderName::from_static("Content-Type"),
            HeaderValue::from_str(content_type.to_str().unwrap()).unwrap(),
        );
    }

    let body_bytes: Bytes = to_bytes(req.into_body(), cfg.gateway.max_body_size)
        .await
        .map_err(|e| {
            eprintln!("Failed to read request body: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let resp = client
        .request(reqwest_method, &service_url)
        .body(body_bytes)
        .headers(client_reqwest_headers)
        .headers(auth_reqwest_headers)
        .header("x-trace-id", utils::trace::generate_trace_id())
        .send()
        .await
        .map_err(|_| StatusCode::BAD_GATEWAY)?;

    let allowed_headers = ["content-type", "content-length", "etag"];

    let mut headers = AxumHeaderMap::new();
    for name in &allowed_headers {
        if let Some(value) = resp.headers().get(*name) {
            headers.insert(
                AxumHeaderName::from_static(name),
                AxumHeaderValue::from_str(value.clone().to_str().unwrap()).unwrap(),
            );
        }
    }

    let status = StatusCode::from_u16(resp.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
    let bytes = resp.bytes().await.map_err(|_| StatusCode::BAD_GATEWAY)?;
    let response = (status, headers, Body::from(bytes)).into_response();
    Ok(response)
}
