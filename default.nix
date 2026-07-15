{pkgs}: let
  lua-resty-websocket = pkgs.luajitPackages.callPackage (
    {
      buildLuarocksPackage,
      fetchFromGitHub,
      fetchurl,
      luaOlder,
    }:
      buildLuarocksPackage {
        pname = "lua-resty-websocket";
        version = "0.07-0";

        knownRockspec =
          (fetchurl {
            url = "https://luarocks.org/manifests/invizory/lua-resty-websocket-0.07-0.rockspec";
            hash = "sha256-VHwMvzh+JKbPvfcS1t8RB3PSQDDHO8ewpse7Q1qzvig=";
          }).outPath;

        src = fetchFromGitHub {
          owner = "openresty";
          repo = "lua-resty-websocket";
          tag = "v0.14";
          hash = "sha256-kzzoQ+wbPpOMFc57K5bRwGFZsWXVeK7DrNWfG0smAUM=";
        };

        disabled = luaOlder "5.1";
      }
  ) {};
in
  pkgs.stdenv.mkDerivation {
    pname = "svc-gateway";
    version = "1.0";

    src = ./lua;

    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';

    passthru = {
      luaDependencies = [
        lua-resty-websocket
        pkgs.luajitPackages.lua-resty-jwt
        pkgs.luajitPackages.lua-resty-http
        pkgs.luajitPackages.cjson
      ];
    };
  }
