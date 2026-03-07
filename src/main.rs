mod config;
mod utils;

use axum::{
    Router,
    body::{Body, Bytes, to_bytes},
    extract::{Request, State},
    http::{
        HeaderMap as AxumHeaderMap, HeaderName as AxumHeaderName, HeaderValue as AxumHeaderValue,
    },
    http::{Response, StatusCode},
    response::IntoResponse,
};
use config::loader::load_config;
use reqwest::{
    Client,
    header::{HeaderMap, HeaderName, HeaderValue},
};
use std::sync::Arc;
use tokio::{
    signal::unix::{SignalKind, signal},
    sync::RwLock,
};

use axum::http::Method as AxumMethod;
use reqwest::Method as ReqwestMethod;
use std::str::FromStr;

use crate::config::RouteConfig;

#[tokio::main]
async fn main() {
    let shared_config = Arc::new(RwLock::new(load_config("config.yaml")));
    println!("Config loaded: {:#?}", shared_config.read().await);

    let app = Router::new()
        .fallback(handler)
        .with_state(shared_config.clone());

    let shared_config_clone = shared_config.clone();
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

    let listener = tokio::net::TcpListener::bind(&shared_config.read().await.gateway.host)
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
    State(config): State<Arc<RwLock<config::GatewayConfig>>>,
    req: Request,
) -> Result<Response<Body>, StatusCode> {
    let cfg = config.read().await;

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

    let mut auth_reqwest_headers = HeaderMap::new();
    if let Some(auth_header) = req.headers().get("Authorization") {
        if let Ok(auth) = auth_header.to_str() {
            if auth.starts_with("Basic ") {
                if matched_route.special_allow_roles.is_none()
                    || !matched_route
                        .special_allow_roles
                        .unwrap()
                        .contains("server")
                {
                    return Ok(Response::builder().status(403).body(Body::empty()).unwrap());
                }

                if let Some(server_name) = utils::server_token_decoder::decode_server_token(
                    &cfg.allowed_server_tokens,
                    &auth[6..],
                ) {
                    auth_reqwest_headers.insert(
                        HeaderName::from_static("eauth-type"),
                        HeaderValue::from_static("server"),
                    );
                    auth_reqwest_headers.insert(
                        HeaderName::from_static("eauth-server-name"),
                        HeaderValue::from_str(&server_name).unwrap(),
                    );
                } else {
                    return Ok(Response::builder().status(401).body(Body::empty()).unwrap());
                }
            } else if auth.starts_with("Bearer ") {
                let user_token_uuid = {
                    match utils::user_token_decoder::decode_user_token(&auth[7..]) {
                        Ok(token) => Some(token.uuid),
                        Err(err) => {
                            println!("{:#?}", err);
                            None
                        }
                    }
                };

                if let Some(uuid) = user_token_uuid {
                    auth_reqwest_headers.insert(
                        HeaderName::from_static("eauth-type"),
                        HeaderValue::from_static("user"),
                    );
                    auth_reqwest_headers.insert(
                        HeaderName::from_static("eauth-user-id"),
                        HeaderValue::from_str(&uuid).unwrap(),
                    );
                    let roles = utils::user_token_decoder::get_user_roles(
                        &cfg.services["svc-users"].base_url,
                        &uuid,
                    )
                    .await
                    .unwrap();

                    auth_reqwest_headers.insert(
                        HeaderName::from_static("eauth-user-roles"),
                        HeaderValue::from_str(&roles.join(",")).unwrap(),
                    );

                    if let Some(allow_roles) = &matched_route.allow_roles {
                        let mut has_access: bool = false;
                        for role in roles {
                            if allow_roles.contains(&role) {
                                has_access = true;
                                break;
                            }
                        }

                        if !has_access {
                            return Ok(Response::builder()
                                .status(403)
                                .body(Body::empty())
                                .unwrap());
                        }
                    }
                } else {
                    return Ok(Response::builder().status(422).body(Body::empty()).unwrap());
                }
            } else {
                return Ok(Response::builder().status(422).body(Body::empty()).unwrap());
            }
        } else {
            return Ok(Response::builder().status(422).body(Body::empty()).unwrap());
        }
    } else {
        if matched_route.allow_roles.is_some() || matched_route.special_allow_roles.is_some() {
            return Ok(Response::builder().status(401).body(Body::empty()).unwrap());
        }

        auth_reqwest_headers.insert(
            HeaderName::from_static("eauth-type"),
            HeaderValue::from_static("guest"),
        );
    }
    let auth_reqwest_headers = auth_reqwest_headers;

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
