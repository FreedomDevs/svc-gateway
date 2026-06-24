use axum::{body::Body, extract::Request, http::Response};
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};

use crate::{
    config::{GatewayConfig, RouteConfig},
    utils::{server_token_decoder, user_token_decoder},
};

pub async fn generate_auth_headers(
    req: &Request,
    matched_route: &RouteConfig,
    cfg: &GatewayConfig,
) -> Result<HeaderMap, axum::http::Response<axum::body::Body>> {
    let mut auth_reqwest_headers = HeaderMap::new();

    let Some(auth_header) = req.headers().get("Authorization") else {
        if matched_route.allow_roles.is_some() || matched_route.special_allow_roles.is_some() {
            return Err(Response::builder().status(401).body(Body::empty()).unwrap());
        }

        auth_reqwest_headers.insert(
            HeaderName::from_static("eauth-type"),
            HeaderValue::from_static("guest"),
        );
        return Ok(auth_reqwest_headers);
    };

    let Ok(auth) = auth_header.to_str() else {
        return Err(Response::builder().status(422).body(Body::empty()).unwrap());
    };

    if auth.starts_with("Basic ") {
        if matched_route.special_allow_roles.is_none()
            || !matched_route
                .special_allow_roles
                .as_ref()
                .unwrap()
                .contains("server")
        {
            return Err(Response::builder().status(403).body(Body::empty()).unwrap());
        }

        let Some(server_name) =
            server_token_decoder::decode_server_token(&cfg.allowed_server_tokens, &auth[6..])
        else {
            return Err(Response::builder().status(401).body(Body::empty()).unwrap());
        };

        auth_reqwest_headers.insert(
            HeaderName::from_static("eauth-type"),
            HeaderValue::from_static("server"),
        );
        auth_reqwest_headers.insert(
            HeaderName::from_static("eauth-server-name"),
            HeaderValue::from_str(&server_name).unwrap(),
        );

        return Ok(auth_reqwest_headers);
    }

    if auth.starts_with("Bearer ") {
        let user_token_uuid = {
            match user_token_decoder::decode_user_token(&auth[7..]) {
                Ok(token) => Some(token.uuid),
                Err(err) => {
                    println!("{:#?}", err);
                    None
                }
            }
        };

        let Some(uuid) = user_token_uuid else {
            return Err(Response::builder().status(422).body(Body::empty()).unwrap());
        };

        auth_reqwest_headers.insert(
            HeaderName::from_static("eauth-type"),
            HeaderValue::from_static("user"),
        );
        auth_reqwest_headers.insert(
            HeaderName::from_static("eauth-user-id"),
            HeaderValue::from_str(&uuid).unwrap(),
        );
        let roles = user_token_decoder::get_user_roles(&cfg.services["svc-users"].base_url, &uuid)
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
                return Err(Response::builder().status(403).body(Body::empty()).unwrap());
            }
        }

        return Ok(auth_reqwest_headers);
    }

    return Err(Response::builder().status(422).body(Body::empty()).unwrap());
}
