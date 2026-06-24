# shell.nix
{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  buildInputs = [
    pkgs.openresty
    pkgs.luaPackages.lua-resty-jwt
    pkgs.luaPackages.lua-resty-http
    pkgs.openssl
  ];

  shellHook = ''
    LUA_PACKAGES_PATH="${pkgs.luaPackages.lua-resty-jwt}/share/lua/5.1/?.lua;${pkgs.luaPackages.lua-resty-jwt}/share/lua/5.1/?/init.lua"
  '';
}
