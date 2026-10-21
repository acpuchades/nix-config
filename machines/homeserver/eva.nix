# eva — the OpenClaw agent (agents/eva). Her mailbox is at Migadu, read over
# IMAP through the credential broker; what she sends leaves through ./mail.nix.
{ pkgsUnstable, ... }:
{
  imports = [
    ../../agents/eva
  ];

  # OpenClaw agent — Telegram-only, loopback gateway, but NOT confined on
  # the host side (no sandbox/grants; see the module header).
  # Needs these two SOPS secrets populated (declared in sops.nix):
  #   sops machines/homeserver/secrets/default.yml
  #     openclaw/eva/telegram-token, openclaw/eva/telegram-userid
  # Auth is the Claude subscription via the Claude CLI runtime — log in once:
  #   sudo -u eva -H claude            # /login, then quit
  # OpenClaw from nixpkgs-unstable (2026.6.33), NOT nixpkgs-26.05's 2026.5.7.
  # Why: 2026.5.7's claude-cli runtime has no handler for Claude Code's
  # permission protocol (control_request/can_use_tool), so a non-allowlisted
  # command hangs ~180s then dies with no Telegram prompt. 2026.6.33 adds the
  # responder (claude-live-session answers can_use_tool → allow under YOLO
  # else a clean deny) AND fixes the bundled-surface hardlink guard upstream
  # (plugin loaders now pass rejectHardlinks:false). Taken from the shared
  # `pkgsUnstable` instance in ./default.nix, whose insecure permit is
  # this package's (openclaw is marked knownVulnerabilities upstream) and is
  # version-agnostic, so it survives unstable's openclaw bumps without
  # editing a version string.
  my.openclaw = {
    # SHARED across all agent instances — the one OpenClaw build they all run.
    package = pkgsUnstable.openclaw;

    # Agents deployed on this host: each is its own module under agents/,
    # imported above (eva: Telegram bot eva_lebbot, own OS user, home,
    # state dir /var/lib/openclaw/eva and openclaw-eva.service). Only
    # `package` is shared between them.
  };
}
