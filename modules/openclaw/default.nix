{
  config,
  lib,
  pkgs,
  ...
}:

#
# openclaw — self-hosted LLM agent (OpenClaw), reachable ONLY through Telegram
# (long-polling; no inbound port). The gateway/control UI is bound to loopback
# so it is reachable locally but never from the LAN.
#
# Two layers, and only one of them is here:
#
#   * WHO CAN TALK TO IT — kept and declarative. The gateway binds 127.0.0.1,
#     Telegram DMs are locked to an explicit numeric-ID allowlist, groups are
#     disabled, and neither the bot token nor the allowed ID ever touches the
#     store or the repo — both arrive as runtime files (telegram.tokenFile /
#     telegram.allowedIdFile), so the module stays agnostic about the secret
#     system behind them (sops-nix, agenix, plain files, …). OpenClaw rewrites
#     its own config at runtime, so it is re-seeded on every start — including
#     re-patching the allowlist from the ID file — to keep this authoritative.
#
#   * WHAT IT CAN DO TO THE HOST — deliberately absent. No systemd sandbox, no
#     polkit rules, no capability grants. Upstream marks this package
#     `knownVulnerabilities` (an LLM parses untrusted content with full system
#     access by default → prompt-injectable), acknowledged below via
#     permittedInsecurePackages. Confinement is to be configured separately.
#
# Auth uses a Claude subscription rather than an Anthropic API key: OpenClaw
# reuses a Claude Code CLI login on this host (`claude -p`), selected by the
# `agentRuntime` option below. Log in once as the agent's own user:
#
#   sudo -u <user> -H claude            # /login, then quit
#   systemctl restart openclaw
#
# That writes ~/.claude/.credentials.json, which OpenClaw picks up. On a box
# where the browser flow is awkward, `claude setup-token` yields a long-lived
# token instead — put it in the state dir's .env as CLAUDE_CODE_OAUTH_TOKEN.
#

let
  cfg = config.my.openclaw;

  # Freeform JSON so my.openclaw.settings can express any key in openclaw.json
  # (see `openclaw config schema`) without the module having to model each one.
  settingsFormat = pkgs.formats.json { };

  # Default read-only safeBins set (exposed via
  # options.my.openclaw.defaultSafeBins so a host can do `defaultSafeBins ++
  # [ ... ]` when overriding a per-instance exec.safeBins).
  defaultSafeBins = [
    # Read-only inspection commands: no filesystem mutation, no exec of
    # other programs, no network. These run unprompted under "allowlist".
    # Anything that writes, deletes, forks a shell, evaluates code, or hits
    # the network is DELIBERATELY absent (sed -i / awk system() / find
    # -exec / xargs / tee / cp / mv / rm / env / curl / git / interpreters
    # …) — those stay gated by `ask`. Append project-specific safe commands
    # in the host config rather than editing this default.
    "cat"
    "head"
    "tail"
    "nl"
    "wc"
    "ls"
    "pwd"
    "stat"
    "file"
    "tree"
    "du"
    "df"
    "free"
    "uptime"
    "date"
    "uname"
    "hostname"
    "whoami"
    "id"
    "groups"
    "which"
    "printenv"
    "echo"
    "grep"
    "egrep"
    "fgrep"
    "rg"
    "jq"
    "cut"
    "sort"
    "uniq"
    "column"
    "basename"
    "dirname"
    "realpath"
    "readlink"
    "diff"
    "comm"
    "sha256sum"
    "md5sum"
    "cksum"
  ];

  # Per-instance NixOS config fragment. Each agent is its own OS user, home,
  # memory/state dir, Telegram bot and loopback gateway service — see the
  # module header. Everything that was a module-wide singleton is derived
  # here from the instance name + its config (icfg).
  mkInstance =
    name: icfg:
    let
      # Provider half of `provider/model` (e.g. "anthropic" from
      # "anthropic/claude-sonnet-4-6"). openclaw 2026.6.x scopes the agent runtime to
      # a provider/model rather than the whole agent, so the runtime backend is pinned
      # on this provider (see defaultConfig).
      runtimeProvider = builtins.head (lib.splitString "/" icfg.model);

      # The agent is a person on this host, not just a daemon: it runs as a real
      # account (`user`, named after the bot) with a real home under /home, where
      # its workspace and its Claude CLI login live. Service-owned state — the
      # config file and session data — stays in /var/lib/openclaw, named after the
      # software that owns it.
      #
      # Groups work in both directions, as they would for any other user:
      #   * to let the agent touch something on this box, add it to that thing's
      #     group (users.users.<user>.extraGroups = [ "share" ]; merges with the
      #     account defined here);
      #   * to let a human read the agent's state without becoming the agent, add
      #     them to the `openclaw` group, which owns the state tree below.
      # Its home is not covered by either — that stays 0700 and private to it.
      homeDir = "/home/${icfg.user}";
      stateDir = "/var/lib/openclaw/${name}";
      configFile = "${stateDir}/openclaw.json";
      credDir = "/run/credentials/openclaw-${name}.service";

      # --- optional email capability (see options.my.openclaw.mail) --------------
      # Read-only mblaze Maildir tools — display, inspect, search, sort/thread and
      # navigate the message sequence; none write to the Maildir, send, or hit the
      # network, so they are safe to run unprompted. NB: the exec gate splits a
      # command into pipeline/chain segments and clears each one independently (it
      # must satisfy `segments.every(...)`), so a pipeline of these read bins — e.g.
      # `mlist | mscan` — runs unprompted because every segment is a safeBin. A
      # prompt is raised only when SOME segment is not itself a safeBin/allowlisted,
      # or the command uses a form that fails analysis (inline-eval like `sh -c`/
      # `python -c` under exec.strictInlineEval, line continuations, etc.).
      mailReadBins = [
        "mscan"
        "mshow"
        "mlist"
        "mhdr"
        "mdirs"
        "mseq"
        "mthread"
        "msort"
        "maddr"
        "magrep"
        "mmime"
        "mpick"
        "mflow"
        "mdate"
      ];

      # Local Maildir MUTATION tools, blessed only when icfg.mail.manageMaildir is on
      # (the owner opts the agent into managing its OWN mailbox). Each edits the
      # local Maildir but neither sends nor fetches over the network, so admitting
      # them stays within the "local mutation, no network" tier: mflag (set/unset
      # flags — read/unread/flagged/trashed), mrefile (move messages between
      # mailboxes), mmkdir (create a mailbox), minc (incorporate new mail), mdeliver
      # (deliver/export a message into a maildir). STILL DELIBERATELY EXCLUDED even
      # when this is on: mcom/mrep/mfwd/mbnc/msuck/mblow (send or fetch over the
      # network — the only blessed outbound path is the recipient-gated send-email),
      # msed (rewrites message content in place, sed -i-style), and mless/mquote
      # (interactive pager / reply-compose helper) — those keep prompting.
      mailManageBins = [
        "mflag"
        "mrefile"
        "mmkdir"
        "minc"
        "mdeliver"
      ];

      # `send-email`: the generic actions/send-email script wrapped so the sender
      # identity ($MAIL_FROM, from icfg.mail.fromAddress) and the sendmail path are
      # pinned by nix — the script itself stays identity-agnostic. Immutable in the
      # store, and the wrapper --set overrides any inherited env, so the agent can
      # neither swap the code nor change the sender. The bin name carries no agent
      # name.
      mailSendBin =
        let
          wrapArgs = [
            "--set SENDMAIL /run/wrappers/bin/sendmail"
          ]
          # Confidential recipients are refused here (see mail.gpg): being on the
          # unprompted list does not make a cleartext send to them acceptable.
          ++ encryptOnlyWrapArgs
          ++ lib.optional (icfg.mail.fromAddress != null) "--set MAIL_FROM ${lib.escapeShellArg icfg.mail.fromAddress}";
        in
        pkgs.runCommandLocal "openclaw-send-email" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            install -Dm0755 ${./actions/send-email} $out/libexec/send-email
            makeWrapper $out/libexec/send-email $out/bin/send-email \
              ${lib.concatStringsSep " \\\n  " wrapArgs}
          '';

      # One exact allowlist rule per pre-blessed recipient: `send-email <addr>`. Any
      # other recipient (or more than one in a single send) fails to match and falls
      # through to the exec `ask` gate — the data-exfiltration guard.
      mailAllowlist = map (addr: "send-email ${addr}") icfg.mail.unpromptedRecipients;

      mailFromDisplay =
        if icfg.mail.fromAddress == null then "the agent's configured address" else icfg.mail.fromAddress;

      # --- confidential mail (OpenPGP) — see options.my.openclaw.mail.gpg -------
      gpgCfg = icfg.mail.gpg;
      gpgEnabled = icfg.mail.enable && gpgCfg.enable;

      # The keyring lives in the SERVICE state dir rather than the agent's ~/.gnupg,
      # and is rebuilt from nix on every start (see gpgSeed). That is what keeps it
      # CLOSED: a key the agent imports at runtime — the obvious move for an
      # injection that wants to encrypt an exfil copy to itself — does not survive a
      # restart, and cannot be selected in the meantime because both wrappers name
      # keys by pinned fingerprint rather than by address.
      gnupgHome = "${stateDir}/gnupg";

      # Flags shared by the seed and both wrappers. Every network path gpg has is
      # off (no dirmngr, no keyserver, no opportunistic import), so the keyring can
      # only ever hold what nix put in it.
      gpgFlags = lib.concatStringsSep " " [
        "--batch"
        "--no-tty"
        "--quiet"
        "--homedir ${gnupgHome}"
        "--disable-dirmngr"
        "--no-auto-key-locate"
        "--no-auto-key-import"
        "--keyserver-options no-auto-key-retrieve"
      ];

      # `address=fingerprint` pairs for send-encrypted-mail (addresses lowercased
      # here so the script's comparison is a plain string match).
      gpgEncryptKeys = lib.concatStringsSep " " (
        map (k: "${lib.toLower k.address}=${k.fingerprint}") gpgCfg.keys
      );

      # Fingerprints decrypt-mail will accept as a trusted signer on inbound mail.
      gpgTrustedSigners = lib.concatStringsSep " " (map (k: k.fingerprint) gpgCfg.keys);

      # Addresses the PLAINTEXT senders must refuse. This is the fail-closed half of
      # the design: confidentiality is a property of the recipient, fixed in nix, so
      # there is no cleartext fallback for the agent to be argued into.
      gpgEncryptOnly = lib.concatStringsSep " " (
        map (k: lib.toLower k.address) (lib.filter (k: k.requireEncryption) gpgCfg.keys)
      );

      # Pinned into send-email/send-trusted-mail only when the feature is on, so an
      # instance without gpg keeps exactly its previous behaviour.
      encryptOnlyWrapArgs = lib.optional gpgEnabled "--set ENCRYPT_ONLY_ADDRESSES ${lib.escapeShellArg gpgEncryptOnly}";

      # `send-encrypted-mail`: the generic actions/send-encrypted-mail script wrapped
      # so the keyring, the gpg binary and the pinned recipient keys come from nix.
      # Self-gating twice over — it refuses any recipient without a pinned key, and
      # has no code path that emits cleartext — so it is safe to bless whole-binary
      # in safeBins. NB: gnupg goes on the WRAPPER's PATH only (gpg-agent/gpgconf
      # need to be resolvable), never on the agent's, so raw `gpg` stays unavailable.
      encryptedMailBin =
        let
          wrapArgs = [
            "--set SENDMAIL /run/wrappers/bin/sendmail"
            "--set GPG ${pkgs.gnupg}/bin/gpg"
            "--set GNUPGHOME ${gnupgHome}"
            "--set ENCRYPT_KEYS ${lib.escapeShellArg gpgEncryptKeys}"
            "--prefix PATH : ${lib.makeBinPath [ pkgs.gnupg pkgs.coreutils ]}"
          ]
          ++ lib.optional (gpgCfg.fingerprint != null) "--set SIGN_KEY ${lib.escapeShellArg gpgCfg.fingerprint}"
          ++ lib.optional (icfg.mail.fromAddress != null) "--set MAIL_FROM ${lib.escapeShellArg icfg.mail.fromAddress}";
        in
        pkgs.runCommandLocal "openclaw-send-encrypted-mail" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            install -Dm0755 ${./actions/send-encrypted-mail} $out/libexec/send-encrypted-mail
            makeWrapper $out/libexec/send-encrypted-mail $out/bin/send-encrypted-mail \
              ${lib.concatStringsSep " \\\n  " wrapArgs}
          '';

      # `decrypt-mail`: read-only and destination-less (it opens a file the agent can
      # already read and reaches no network), so it is safe to bless whole-binary. It
      # reports the signature verdict against the pinned signer set; deciding what a
      # verdict permits is the skill's job, not the wrapper's.
      decryptMailBin =
        pkgs.runCommandLocal "openclaw-decrypt-mail" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            install -Dm0755 ${./actions/decrypt-mail} $out/libexec/decrypt-mail
            makeWrapper $out/libexec/decrypt-mail $out/bin/decrypt-mail \
              --set GPG ${pkgs.gnupg}/bin/gpg \
              --set GNUPGHOME ${gnupgHome} \
              --set TRUSTED_SIGNERS ${lib.escapeShellArg gpgTrustedSigners} \
              --prefix PATH : ${lib.makeBinPath [ pkgs.gnupg pkgs.coreutils ]}
          '';

      # Rebuild the keyring from nix at every start: kill any agent left over from
      # the previous run, wipe the home, re-import the agent's own secret key from
      # the systemd credential and each owner public key from the store. Fail-closed
      # throughout — a missing or unreadable secret key leaves a keyring that cannot
      # decrypt or sign, which stops confidential mail rather than downgrading it.
      gpgSeed = lib.optionalString gpgEnabled ''
        ${pkgs.gnupg}/bin/gpgconf --homedir ${gnupgHome} --kill gpg-agent >/dev/null 2>&1 || true
        rm -rf ${gnupgHome}
        install -d -m 0700 ${gnupgHome}
        if [ -r "''${CREDENTIALS_DIRECTORY:-}/mail-gpg-key" ]; then
          ${pkgs.gnupg}/bin/gpg ${gpgFlags} --import "''${CREDENTIALS_DIRECTORY}/mail-gpg-key" \
            || echo "[openclaw] WARN: could not import the agent's OpenPGP secret key; confidential mail fails closed" >&2
        else
          echo "[openclaw] WARN: no OpenPGP secret key available (mail.gpg.secretKeyFile); confidential mail fails closed" >&2
        fi
        ${lib.concatMapStrings (k: ''
          ${pkgs.gnupg}/bin/gpg ${gpgFlags} --import ${k.publicKeyFile} \
            || echo "[openclaw] WARN: could not import the OpenPGP public key for ${k.address}" >&2
        '') gpgCfg.keys}
        ${pkgs.gnupg}/bin/gpgconf --homedir ${gnupgHome} --kill gpg-agent >/dev/null 2>&1 || true
      '';

      # `request-trusted-url`: the generic actions/request-trusted-url script wrapped
      # so the allowed-host globs ($TRUSTED_SITES) and the curl binary ($CURL) are
      # pinned by nix — the script stays generic and the agent cannot widen the host
      # set or swap the code. Self-gating (refuses any non-trusted host), so it is
      # safe to bless whole-binary in safeBins.
      requestUrlBin =
        pkgs.runCommandLocal "openclaw-request-trusted-url" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            install -Dm0755 ${./actions/request-trusted-url} $out/libexec/request-trusted-url
            makeWrapper $out/libexec/request-trusted-url $out/bin/request-trusted-url \
              --set CURL ${lib.getExe pkgs.curl} \
              --set TRUSTED_SITES ${lib.escapeShellArg (lib.concatStringsSep " " icfg.actions.requestUrl.trustedSites)}
          '';

      # `send-trusted-mail`: the generic actions/send-trusted-mail script wrapped so
      # the trusted recipient set ($TRUSTED_ADDRESSES), the sender ($MAIL_FROM) and
      # sendmail ($SENDMAIL) are pinned by nix. Self-gating (refuses any non-trusted
      # recipient), so it is safe to bless whole-binary in safeBins.
      trustedMailBin =
        let
          wrapArgs = [
            "--set SENDMAIL /run/wrappers/bin/sendmail"
            "--set TRUSTED_ADDRESSES ${lib.escapeShellArg (lib.concatStringsSep " " icfg.actions.trustedMail.trustedAddresses)}"
          ]
          ++ encryptOnlyWrapArgs
          ++ lib.optional (icfg.mail.fromAddress != null) "--set MAIL_FROM ${lib.escapeShellArg icfg.mail.fromAddress}";
        in
        pkgs.runCommandLocal "openclaw-send-trusted-mail" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            install -Dm0755 ${./actions/send-trusted-mail} $out/libexec/send-trusted-mail
            makeWrapper $out/libexec/send-trusted-mail $out/bin/send-trusted-mail \
              ${lib.concatStringsSep " \\\n  " wrapArgs}
          '';

      # `generate-image`: the generic actions/generate-image script wrapped so the
      # model, token-file path, optional reference image, API base and tool paths are
      # all pinned by nix — the script stays generic and the agent cannot swap the
      # code, the model, or the endpoint. Destination-pinned (always the configured
      # generateContent endpoint), so it is safe to bless whole-binary in safeBins:
      # the only agent-controlled inputs are the prompt and the output path (in its
      # own tree). NB: the API key stays a runtime FILE (tokenFile) — never a nix
      # value — so it does not enter the store or this public repo.
      generateImageBin =
        pkgs.runCommandLocal "openclaw-generate-image" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            install -Dm0755 ${./actions/generate-image} $out/libexec/generate-image
            makeWrapper $out/libexec/generate-image $out/bin/generate-image \
              --prefix PATH : ${
                lib.makeBinPath [
                  pkgs.curl
                  pkgs.jq
                  pkgs.coreutils
                ]
              } \
              --set GENIMG_MODEL ${lib.escapeShellArg icfg.actions.generateImage.model} \
              --set GENIMG_TOKEN_FILE ${lib.escapeShellArg icfg.actions.generateImage.tokenFile} \
              ${
                lib.optionalString (
                  icfg.actions.generateImage.referenceImage != null
                ) "--set GENIMG_DEFAULT_REFERENCE ${lib.escapeShellArg icfg.actions.generateImage.referenceImage}"
              } \
              ${
                lib.optionalString (
                  icfg.actions.generateImage.referenceRoot != null
                ) "--set GENIMG_REFERENCE_ROOT ${lib.escapeShellArg icfg.actions.generateImage.referenceRoot}"
              } \
              ${lib.optionalString (
                icfg.actions.generateImage.apiBase != null
              ) "--set GENIMG_API_BASE ${lib.escapeShellArg icfg.actions.generateImage.apiBase}"}
          '';

      # `check-weather`: the generic actions/check-weather script wrapped so the API
      # key file, units, language, default location and endpoint are pinned by nix.
      # Destination-fixed (always the configured OpenWeatherMap endpoint), so it is
      # safe to bless whole-binary in safeBins. The API key stays a runtime FILE
      # (tokenFile), never a nix value.
      checkWeatherBin =
        pkgs.runCommandLocal "openclaw-check-weather" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            install -Dm0755 ${./actions/check-weather} $out/libexec/check-weather
            makeWrapper $out/libexec/check-weather $out/bin/check-weather \
              --prefix PATH : ${
                lib.makeBinPath [
                  pkgs.curl
                  pkgs.jq
                  pkgs.coreutils
                ]
              } \
              --set WEATHER_TOKEN_FILE ${lib.escapeShellArg icfg.actions.checkWeather.tokenFile} \
              --set WEATHER_UNITS ${lib.escapeShellArg icfg.actions.checkWeather.units} \
              --set WEATHER_LANG ${lib.escapeShellArg icfg.actions.checkWeather.lang} \
              ${
                lib.optionalString (
                  icfg.actions.checkWeather.defaultLocation != null
                ) "--set WEATHER_DEFAULT_LOCATION ${lib.escapeShellArg icfg.actions.checkWeather.defaultLocation}"
              } \
              ${lib.optionalString (
                icfg.actions.checkWeather.apiBase != null
              ) "--set WEATHER_API_BASE ${lib.escapeShellArg icfg.actions.checkWeather.apiBase}"}
          '';

      # `solve-captcha`: the generic actions/solve-captcha script wrapped so the API
      # key file, the endpoint, the allowed page hosts, the image root and the
      # timeouts are pinned by nix — the script stays generic and the agent can
      # neither swap the code nor widen the host set. Destination-pinned (always the
      # configured 2Captcha endpoint) AND self-gating on the page host, so it is safe
      # to bless whole-binary. Two properties keep it from becoming an outbound
      # channel: the wrapper BUILDS the task JSON itself from flags (only the
      # "…Proxyless" task types exist for the agent, so no proxy/UA/cookie fields can
      # be smuggled in and the farm cannot be used as a relay), and the page URL must
      # match allowedSites. What the agent does control — the page URL, the site key
      # and an image body — is low-bandwidth and goes only to 2Captcha; the image is
      # additionally confined to its own tree. NB: the API key stays a runtime FILE
      # (tokenFile), never a nix value, so it does not enter the store or this repo.
      solveCaptchaBin =
        pkgs.runCommandLocal "openclaw-solve-captcha" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            install -Dm0755 ${./actions/solve-captcha} $out/libexec/solve-captcha
            makeWrapper $out/libexec/solve-captcha $out/bin/solve-captcha \
              --prefix PATH : ${
                lib.makeBinPath [
                  pkgs.curl
                  pkgs.jq
                  pkgs.coreutils
                ]
              } \
              --set CAPTCHA_TOKEN_FILE ${lib.escapeShellArg icfg.actions.solveCaptcha.tokenFile} \
              --set CAPTCHA_ALLOWED_SITES ${
                lib.escapeShellArg (lib.concatStringsSep " " icfg.actions.solveCaptcha.allowedSites)
              } \
              --set CAPTCHA_TIMEOUT ${toString icfg.actions.solveCaptcha.timeoutSeconds} \
              --set CAPTCHA_POLL_INTERVAL ${toString icfg.actions.solveCaptcha.pollIntervalSeconds} \
              ${
                lib.optionalString (
                  icfg.actions.solveCaptcha.imageRoot != null
                ) "--set CAPTCHA_IMAGE_ROOT ${lib.escapeShellArg icfg.actions.solveCaptcha.imageRoot}"
              } \
              ${
                lib.optionalString (
                  icfg.actions.solveCaptcha.softId != null
                ) "--set CAPTCHA_SOFT_ID ${lib.escapeShellArg icfg.actions.solveCaptcha.softId}"
              } \
              ${lib.optionalString (
                icfg.actions.solveCaptcha.apiBase != null
              ) "--set CAPTCHA_API_BASE ${lib.escapeShellArg icfg.actions.solveCaptcha.apiBase}"}
          '';

      # `check-calendar`: list upcoming events from an .ics calendar (python +
      # icalendar + recurring-ical-events). It takes the calendar SOURCE directly
      # — an https:// URL (fetched by DELEGATING to request-trusted-url, so the
      # fetch inherits the exact same trusted-host allowlist, GET-only method and
      # no-redirect policy — no new outbound surface), or a local .ics file /
      # stdin (parsed offline). Safe to bless whole-binary: local parsing is
      # network-free, and the only network path is the already-hardened,
      # host-gated request-trusted-url binary baked into its PATH below. This
      # collapses the old two-segment `request-trusted-url <url> | parse-ics`
      # pipe into one command (which the exec gate prefers).
      checkCalendarPython = pkgs.python3.withPackages (ps: [
        ps.icalendar
        ps.recurring-ical-events
      ]);
      checkCalendarBin =
        pkgs.runCommandLocal "openclaw-check-calendar" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            install -Dm0755 ${./actions/check-calendar} $out/libexec/check-calendar
            makeWrapper $out/libexec/check-calendar $out/bin/check-calendar \
              --prefix PATH : ${lib.makeBinPath [ checkCalendarPython requestUrlBin ]}
          '';

      # `offline CMD …`: run CMD in a throwaway user+network namespace with NO
      # network interfaces (only a down `lo`), so a network-capable tool cannot reach
      # anything off-box regardless of its arguments — the fail-safe way to bless
      # converters like ffmpeg/pandoc/xmllint unprompted without reopening a data-
      # exfil channel (`offline ffmpeg -i http://evil/…` simply cannot connect). It
      # only ever REMOVES capability, and the unprivileged userns needs no setuid.
      # The bare tool (no `offline` prefix) stays gated. See exec.netIsolatedBins.
      offlineLauncher = pkgs.writeShellScriptBin "offline" ''
        exec ${pkgs.util-linux}/bin/unshare --user --map-root-user --net -- "$@"
      '';

      # Full-command globs blessing `offline <bin> …` for each netIsolatedBin, so the
      # network-isolated form runs unprompted while the bare binary keeps prompting.
      netIsolateAllowlist = map (b: "offline ${b}*") icfg.exec.netIsolatedBins;

      # Skill generators live in ./skills/*.nix — one file per skill. They are
      # config-templated (they interpolate icfg/homeDir/mailFromDisplay), so unlike
      # the static scripts in ./actions/ they are FUNCTIONS returning a writeTextDir,
      # imported with the shared skillArgs below. (Distinct from any repo-root
      # ./skills of static, agent-shared SKILL.md content — a different layer.)
      skillArgs = { inherit pkgs lib icfg homeDir mailFromDisplay; };
      mailSkillsDir = import ./skills/mail.nix skillArgs;
      captchaSkillsDir = import ./skills/captcha.nix skillArgs;
      policySkillsDir = import ./skills/policy.nix skillArgs;
      toolkitSkillsDir = import ./skills/toolkit.nix skillArgs;
      projectsSkillsDir = import ./skills/projects.nix skillArgs;
      toolkitHasContent =
        icfg.toolkit.python != [ ]
        || icfg.toolkit.r != [ ]
        || icfg.toolkit.cli != [ ]
        || icfg.toolkit.notes != "";

      # OpenClaw's bundled-plugin loader opens each plugin "public surface" through a
      # boundary check that REJECTS any file with st_nlink > 1 (openBoundaryFileSync
      # { rejectHardlinks: true }, enforced once in dist/safe-open-sync-*.js). That is
      # a hardening against a surface file being hardlinked in from outside the
      # package boundary — but on NixOS with nix.settings.auto-optimise-store = true
      # the store hardlink-dedupes identical files, so EVERY bundled surface lands at
      # nlink >= 2 and the loader throws "Unable to open bundled plugin public surface
      # <plugin>/<file>".
      #
      # It bites selectively: the Claude path never trips it, because the claude-cli
      # agentRuntime shells out to the `claude` binary and never loads an internal
      # provider surface. Any NATIVE provider does load one — so a google/gemini
      # failover (or the duckduckgo web-search plugin) fails on EVERY dispatch, not
      # just when the failover fires, because the model-routing setup loads the
      # provider's surface up front. That is what silently broke all of eva's traffic
      # the moment a gemini fallback was configured.
      #
      # Neutralize BOTH nlink>1 enforcement sites so hardlinked store files are
      # accepted. openBoundaryFileSync (in safe-open-sync-*.js) rejects hardlinks
      # TWICE: once on the pre-open lstat (preOpenStat) and again on the post-open
      # fstat (openedStat) — an open-then-verify pair guarding against a TOCTOU swap.
      # The store dedups identical files to nlink>=2, so both fire. The original
      # patch disabled only the preOpenStat check, so google/gemini (and any native
      # provider) surfaces STILL failed to load on every dispatch via the openedStat
      # check — silently breaking all of eva's traffic once a gemini fallback was set.
      # The realpath / allowed-type / symlink / max-bytes checks are left intact;
      # only the two nlink>1 rejections are disabled. Safe here: the files are our own
      # read-only /nix/store on a single-tenant host — the guard buys nothing against
      # a hardlink attack and only fights the store's own dedup. Each --replace-fail
      # makes a version bump that moves/renames either expression fail the build
      # loudly rather than silently shipping the broken (unpatched) loader.
      # HARDLINK-GUARD WORKAROUND REMOVED 2026-07-27 — testing the upstream fix
      # directly. 2026.5.x shipped a bundled-plugin loader that rejected any surface
      # file with st_nlink > 1 (openBoundaryFileSync { rejectHardlinks:true } in
      # safe-open-sync-*.js); with NixOS `auto-optimise-store` dedup (nlink>=2) that
      # broke every bundled surface, so we used to `overrideAttrs` the two rejection
      # sites to `false`. openclaw 2026.6.x FIXED it upstream — the loaders now pass
      # `rejectHardlinks: false` (facade-loader / security-runtime in the 2026.6.33
      # source) — so we now run the package UNMODIFIED to confirm the fix holds under
      # our store settings. If bundled surfaces / native providers fail to load on
      # dispatch again ("Unable to open bundled plugin public surface …"), restore the
      # overrideAttrs patch from git history. Name kept (referenced throughout); it is
      # now simply the unmodified package.
      openclawPatched = cfg.package;

      # The config file is re-seeded from Nix on every start, so it is assembled
      # here in three layers with a clear precedence:
      #
      #   defaultConfig  <  icfg.settings  <  enforcedConfig
      #
      # i.e. the module's defaults can be overridden by the user's declarative
      # settings, but the security-critical keys are forced on top and cannot be
      # overridden by settings (or by anything the agent writes at runtime, since
      # the whole file is rebuilt from this each start).

      # Sensible defaults the user may override via my.openclaw.settings.
      defaultConfig = {
        gateway.port = icfg.port;
        agents.defaults = {
          model = {
            primary = icfg.model;
          }
          // lib.optionalAttrs (icfg.fallbackModels != [ ]) {
            # Ordered failover: OpenClaw tries these in turn when the primary model
            # errors. This is failover, not on-demand escalation — a stronger model
            # here only runs when the primary call fails.
            fallbacks = icfg.fallbackModels;
          };
          workspace = "${homeDir}/workspace";
        }
        // lib.optionalAttrs icfg.memorySearch.enable {
          # Embedding-backed recall over the agent's memory files. Provider is the
          # host's choice (local keyless GGUF by default); the local model path and an
          # optional remote model name are folded in only when set, so the emitted
          # config matches whichever backend was picked.
          memorySearch = {
            enabled = true;
            provider = icfg.memorySearch.provider;
          }
          // lib.optionalAttrs (icfg.memorySearch.localModelPath != null) {
            local.modelPath = "${icfg.memorySearch.localModelPath}";
          }
          // lib.optionalAttrs (icfg.memorySearch.model != null) {
            model = icfg.memorySearch.model;
          };
        }
        // lib.optionalAttrs icfg.heartbeat.enable {
          # Periodic autonomous turns, assembled from my.openclaw.heartbeat. A
          # default (overridable via icfg.settings), not an enforced key.
          heartbeat = {
            every = icfg.heartbeat.every;
            activeHours = {
              start = icfg.heartbeat.activeHours.start;
              end = icfg.heartbeat.activeHours.end;
            }
            // lib.optionalAttrs (icfg.heartbeat.activeHours.timezone != null) {
              timezone = icfg.heartbeat.activeHours.timezone;
            };
          };
        };
        channels.telegram = {
          enabled = true;
          tokenFile = "${credDir}/telegram-token"; # real file (symlinks rejected)
        };
      }
      // lib.optionalAttrs (icfg.agentRuntime != null) {
        # Agent runtime backend, PROVIDER-scoped (openclaw 2026.6.x). 2026.5.x set
        # agents.defaults.agentRuntime.id; that key is now REJECTED ("agents.defaults:
        # Invalid input") — the runtime is pinned per provider/model instead. We pin it
        # on the provider of the primary model (runtimeProvider), so e.g. "claude-cli"
        # makes that provider's models run via the Claude Code subscription login;
        # "openclaw" selects the built-in native runtime.
        models.providers.${runtimeProvider}.agentRuntime.id = icfg.agentRuntime;
      }
      // lib.optionalAttrs icfg.tts.enable {
        # Reply text-to-speech, assembled from the my.openclaw.tts options. Lives in
        # defaultConfig (a preference, not a security invariant), so icfg.settings can
        # still fine-tune it. The provider's voice/model go under the persona's
        # open-additionalProps providers.<provider> slot; the provider API key is
        # NOT put here — it is read from the environment (e.g. ELEVENLABS_API_KEY),
        # so no secret enters the store.
        messages.tts = {
          # NB: no `enabled` key. OpenClaw 2026.5.x treats messages.tts.enabled as a
          # LEGACY key and rejects the config at load ("messages.tts.enabled is
          # legacy; use messages.tts.auto") — emitting it alongside `auto` fails the
          # ExecStartPre `config patch` validation and crash-loops the seed. `auto`
          # is now the sole on/off + when-to-speak control ("off" = capability
          # present but never auto-speaks).
          auto = icfg.tts.auto;
          mode = icfg.tts.mode;
          provider = icfg.tts.provider;
          maxTextLength = icfg.tts.maxTextLength;
          timeoutMs = icfg.tts.timeoutMs;
          persona = "default";
          personas.default = {
            label = icfg.tts.label;
            provider = icfg.tts.provider;
            providers.${icfg.tts.provider} = {
              voiceId = icfg.tts.voiceId;
            }
            // lib.optionalAttrs (icfg.tts.modelId != null) {
              modelId = icfg.tts.modelId;
            }
            // lib.optionalAttrs (icfg.tts.speed != null) {
              voiceSettings.speed = icfg.tts.speed;
            };
          };
        };
      }
      // lib.optionalAttrs icfg.stt.enable {
        # Inbound speech-to-text: transcribe voice notes so eva can act on them.
        # A whisper.cpp CLI entry in the media-audio model list. OpenClaw special-
        # cases `whisper-cli`: it transcodes the inbound Telegram OGG/Opus to
        # 16 kHz mono WAV via ffmpeg and reads whisper's `.txt` sidecar, so no
        # wrapper is needed; the transcript is then fed to the agent like a typed
        # message. Lives in defaultConfig (a preference), so icfg.settings can tune it.
        tools.media.audio = {
          enabled = true;
          models = [
            {
              type = "cli";
              command = "whisper-cli";
              args = [
                "-m"
                "${icfg.stt.model}"
                "-l"
                icfg.stt.language
                "-otxt"
                "-of"
                "{{OutputBase}}"
                "-np"
                "-nt"
                "{{MediaPath}}"
              ];
              timeoutSeconds = icfg.stt.timeoutSeconds;
            }
          ];
        };
      };

      # Non-negotiable security invariants. Access is locked to an explicit
      # numeric-ID allowlist and groups are disabled; the gateway stays loopback.
      # Merged LAST so a stray value in icfg.settings can never open access.
      enforcedConfig = {
        gateway = {
          # This build of OpenClaw takes a bind *mode* keyword, not an IP, and
          # refuses to start unless gateway.mode is set. "local" + "loopback" is
          # the 127.0.0.1-only posture we want; an IP string here is rejected.
          mode = "local";
          bind = "loopback";
        };
        channels.telegram = {
          dmPolicy = "allowlist";
          # The allowlisted ID is a runtime secret from icfg.telegram.allowedIdFile,
          # not known at eval time — so the store config is written FAIL-CLOSED
          # (nobody allowed) and the seed script patches the real ID(s) over these
          # two keys on every start (see ExecStartPre). If the file is missing/empty,
          # these stay [] and the bot answers no one, rather than opening up.
          allowFrom = [ ];
          groupPolicy = "disabled";
        };
        commands.ownerAllowFrom = [ ];

        # Exec policy is operator-authoritative, not agent-writable: it is forced on
        # here from the my.openclaw.exec options and re-patched every start, so a
        # prompt-injected agent cannot flip itself to security="full", turn off the
        # approval prompt, or slip extra binaries into the safe list at runtime. The
        # per-agent approvals allowlist (path globs) is separate mutable state and is
        # deliberately NOT pinned here — that is the human-gated approve-and-remember
        # surface. Other tools.exec.* keys (timeouts, backgroundMs, …) stay settable
        # via icfg.settings; only these safety keys are pinned.
        tools.exec = {
          security = icfg.exec.security;
          ask = icfg.exec.ask;
          strictInlineEval = icfg.exec.strictInlineEval;
          safeBins =
            icfg.exec.safeBins
            ++ lib.optionals icfg.mail.enable mailReadBins
            ++ lib.optionals (icfg.mail.enable && icfg.mail.manageMaildir) mailManageBins
            # The trusted-* action wrappers SELF-GATE their destination (refusing
            # anything off the trusted list), so they are safe to bless whole-binary:
            # any invocation either targets a trusted destination or exits non-zero.
            ++ lib.optionals icfg.actions.requestUrl.enable [ "request-trusted-url" ]
            ++ lib.optionals icfg.actions.trustedMail.enable [ "send-trusted-mail" ]
            # send-encrypted-mail refuses any recipient without a pinned key and has
            # no cleartext path at all; decrypt-mail is read-only and reaches no
            # network. Both are therefore safe whole-binary. Raw `gpg` is NOT here
            # and NOT on the agent's PATH — these wrappers are its entire OpenPGP
            # surface (see mail.gpg).
            ++ lib.optionals gpgEnabled [
              "send-encrypted-mail"
              "decrypt-mail"
            ]
            # generate-image is likewise destination-pinned (fixed model/endpoint), so
            # blessing the whole binary only ever hits the configured image endpoint.
            ++ lib.optionals icfg.actions.generateImage.enable [ "generate-image" ]
            # check-weather is destination-pinned to the configured weather endpoint.
            ++ lib.optionals icfg.actions.checkWeather.enable [ "check-weather" ]
            # solve-captcha is destination-pinned to the configured solving endpoint
            # AND self-gates the page host against allowedSites, so blessing the whole
            # binary opens no destination the operator has not already blessed.
            ++ lib.optionals icfg.actions.solveCaptcha.enable [ "solve-captcha" ]
            # check-calendar only ever does local .ics parsing plus a fetch that
            # DELEGATES to the host-gated request-trusted-url binary, so blessing it
            # whole-binary opens no exfil channel beyond what request-trusted-url
            # already allows.
            ++ lib.optionals icfg.actions.checkCalendar.enable [ "check-calendar" ];
        }
        // lib.optionalAttrs (icfg.exec.safeBinProfiles != { }) {
          safeBinProfiles = icfg.exec.safeBinProfiles;
        };
      };

      # Skill directories the module ships, loaded between the module defaults and
      # the host's icfg.settings (so the host can still override but need not wire
      # them): the check-email skill (when mail is on), the solve-captcha workflow
      # skill (when that action is on) and the always-on policy skill that tells the
      # agent what it may/must-not do and to prefer the sanctioned action wrappers
      # over raw tools.
      moduleSkillDirs =
        lib.optional icfg.mail.enable "${mailSkillsDir}"
        ++ lib.optional icfg.actions.solveCaptcha.enable "${captchaSkillsDir}"
        ++ lib.optional toolkitHasContent "${toolkitSkillsDir}"
        ++ lib.optional icfg.projects.enable "${projectsSkillsDir}"
        ++ [ "${policySkillsDir}" ];

      # WHY WE STAGE SKILLS INTO A WRITABLE DIR INSTEAD OF POINTING extraDirs AT THE
      # STORE:
      #
      # OpenClaw's skill loader silently drops any SKILL.md whose inode is hardlinked
      # (nlink>=2 — its `rejectHardlinks` guard), and `auto-optimise-store = true`
      # dedups every store file into `.links/` (nlink>=2). So extraDirs pointing at
      # the /nix/store skill dirs loads ZERO skills — proven with `openclaw skills
      # check` → Total 0, including the always-on `policy` (security) skill, which
      # meant the agent ran with none of its module skills in effect. This is the
      # skills-loader analogue of the plugin hardlink guard tracked in CLAUDE.md;
      # 2026.6.x fixed only the *plugin* loader (`rejectHardlinks:false`), not this.
      #
      # Fix: at start, `cp` each skill tree into a per-agent dir under /var/lib (not
      # auto-optimised), giving every file a fresh inode (nlink=1) the loader
      # accepts. The dir is DEDICATED (`nix-skills`, not `skills`): the seed wipes and
      # rebuilds it on every start, and OpenClaw's own `skills install`/workshop write
      # into the agent WORKSPACE (its own `skills` dir), so a dedicated name keeps our
      # rm -rf from ever clobbering a skill the agent installed or authored itself.
      skillsStageDir = "${stateDir}/nix-skills";
      skillsStageSeed = lib.optionalString (moduleSkillDirs != [ ]) ''
        # Rebuild the skill staging tree from scratch on EVERY start, so a
        # `nixos-rebuild switch` (which restarts the unit when this script's store
        # path changes) always overwrites it with the current skills — and stale
        # skills from a prior generation never linger.
        rm -rf ${skillsStageDir}
        install -d -m 0750 ${skillsStageDir}
        for d in ${lib.escapeShellArgs moduleSkillDirs}; do
          # `cp` (no --preserve=links) copies content into new inodes, breaking the
          # store's hardlinks; each store dir holds exactly one `<name>/SKILL.md`.
          cp -rL --no-preserve=mode,ownership "$d"/. ${skillsStageDir}/
        done
        chmod -R u+w ${skillsStageDir}
      '';
      mailConfig = lib.optionalAttrs (moduleSkillDirs != [ ]) {
        skills.load.extraDirs = [ skillsStageDir ];
      };

      fullConfig = lib.recursiveUpdate (lib.recursiveUpdate (lib.recursiveUpdate defaultConfig mailConfig) icfg.settings) enforcedConfig;

      # The config blueprint, rendered to the store as plain JSON. It holds NO
      # secrets — the bot token is a systemd credential and the allowlisted ID is
      # patched in at start from icfg.telegram.allowedIdFile — so the store is a safe
      # home for it, and the module needs no knowledge of sops/agenix/etc.
      configTemplate = settingsFormat.generate "openclaw.json" fullConfig;

      # The operator-declared exec-approval globs, rendered as ONE JSON file in the
      # openclaw exec-approvals schema (pattern-only entries — OpenClaw backfills the
      # id/lastUsedAt fields itself the first time it reads the file). Deterministic
      # and secret-free, so the nix store is a fine home for it.
      execApprovalsSeed = settingsFormat.generate "openclaw-exec-approvals.json" {
        version = 1;
        socket = { };
        defaults = { };
        agents."*".allowlist = map (pattern: { inherit pattern; }) (
          icfg.exec.allowlist ++ lib.optionals icfg.mail.enable mailAllowlist ++ netIsolateAllowlist
        );
      };

      # Fast, Node-free seed: union the declared globs into the agent's live
      # exec-approvals.json with a SINGLE jq call, replacing the old loop that ran
      # one ~1.4s `openclaw approvals allowlist add` process per glob (~34 of them,
      # which overran the gateway's 90s start-pre timeout and crash-looped it). The
      # union is by pattern string, so the agent's own approve-and-remember entries
      # survive across restarts; a failed merge warns and leaves the file untouched.
      #
      # PATH (openclaw 2026.6.x): the live exec-approvals file lives in the STATE DIR
      # (`${stateDir}/exec-approvals.json`), which is what the runtime reads —
      # `resolveExecApprovalsFromFile` resolves `join(stateDir, "exec-approvals.json")`.
      # 2026.5.x read it from `~/.openclaw/exec-approvals.json`; seeding the old path
      # on 2026.6.x silently left the whole operator allowlist UNLOADED (every command
      # missed → prompted/denied). Since the runtime reads this JSON each start, the
      # reseed-every-start union still holds.
      allowlistSeedMerge = ''
        approvalsFile=${stateDir}/exec-approvals.json
        mkdir -p "$(dirname "$approvalsFile")"
        if [ -f "$approvalsFile" ]; then liveSrc="$approvalsFile"; else liveSrc=${execApprovalsSeed}; fi
        tmp="$(mktemp)"
        if ${lib.getExe pkgs.jq} -s '
              .[0] as $seed | .[1] as $live
              | ($live.agents["*"].allowlist // [])            as $cur
              | ($cur | map(.pattern))                          as $have
              | ($seed.agents["*"].allowlist
                 | map(select((.pattern) as $p | ($have | index($p)) | not))) as $add
              | $live
              | .version     //= 1
              | .socket      //= {}
              | .defaults    //= {}
              | .agents      //= {}
              | .agents["*"] //= {}
              | .agents["*"].allowlist = ($cur + $add)
            ' ${execApprovalsSeed} "$liveSrc" > "$tmp"; then
          install -m 0600 "$tmp" "$approvalsFile"
        else
          echo "[openclaw] WARN: exec-approvals seed merge failed; leaving existing file untouched" >&2
        fi
        rm -f "$tmp"
      '';
    in
    {
      # Fail at eval (not runtime) on a memory-search misconfig: the local embedder
      # can't run without a GGUF model, and a remote provider can't run without its
      # key — so at least require the model file for the local backend here.
      assertions = [
        {
          assertion =
            icfg.memorySearch.enable && icfg.memorySearch.provider == "local"
            -> icfg.memorySearch.localModelPath != null;
          message = "my.openclaw.memorySearch: provider = \"local\" requires memorySearch.localModelPath (a GGUF embedding model, e.g. via pkgs.fetchurl).";
        }
        {
          assertion = icfg.mail.gpg.enable -> icfg.mail.enable;
          message = "my.openclaw.instances.${name}.mail.gpg: requires mail.enable — confidential mail is the mail capability, encrypted.";
        }
        {
          # Without a key there is nothing to encrypt to and no signature to
          # verify, so the feature would only ever refuse — catch it at eval.
          assertion = icfg.mail.gpg.enable -> icfg.mail.gpg.keys != [ ];
          message = "my.openclaw.instances.${name}.mail.gpg: needs at least one entry in `keys` (an owner address + pinned fingerprint + public key file).";
        }
        {
          assertion = lib.all (
            k: builtins.match "[0-9A-Fa-f]{40}" k.fingerprint != null
          ) icfg.mail.gpg.keys;
          message = "my.openclaw.instances.${name}.mail.gpg.keys: each `fingerprint` must be a full 40-character hex OpenPGP fingerprint with no spaces.";
        }
        {
          assertion =
            icfg.mail.gpg.fingerprint == null
            || builtins.match "[0-9A-Fa-f]{40}" icfg.mail.gpg.fingerprint != null;
          message = "my.openclaw.instances.${name}.mail.gpg.fingerprint: must be a full 40-character hex OpenPGP fingerprint with no spaces.";
        }
      ];

      # Upstream flags this package insecure on purpose. Acknowledge explicitly;
      # bump the version suffix when the packaged OpenClaw is updated.
      nixpkgs.config.permittedInsecurePackages = [ "openclaw-${cfg.package.version}" ];

      # ffmpeg must be a *system* package (not just on the service PATH): the STT
      # pipeline resolves it via requireSystemBin, which only trusts fixed dirs
      # like /run/current-system/sw/bin — the system profile, i.e. this list. The
      # SAME is true for any tool the agent runs unprompted: OpenClaw's safe-bin
      # check trusts resolved binaries by directory, and PATH entries are never
      # auto-trusted — so a safeBin present only on the service `path` gets found
      # but NOT honored as safe. jq and rg are in the module's DEFAULT safeBins yet
      # were shipped by neither list (dead references); ship them here. icfg.extra
      # Packages likewise go here (trusted + resolvable) AND on the service `path`
      # below (so bash -c can also resolve them) — belt-and-braces across both
      # resolution paths.
      environment.systemPackages = [
        openclawPatched
        pkgs.claude-code
        pkgs.jq
        pkgs.ripgrep
      ]
      ++ lib.optionals icfg.stt.enable [ pkgs.ffmpeg-headless ]
      ++ lib.optionals icfg.mail.enable [
        mailSendBin
        pkgs.mblaze
      ]
      # The wrappers only — deliberately NOT pkgs.gnupg, so the agent has no raw
      # `gpg` to reach for (it carries its own network and key-import surface).
      ++ lib.optionals gpgEnabled [
        encryptedMailBin
        decryptMailBin
      ]
      ++ lib.optionals icfg.actions.requestUrl.enable [ requestUrlBin ]
      ++ lib.optionals icfg.actions.trustedMail.enable [ trustedMailBin ]
      ++ lib.optionals icfg.actions.generateImage.enable [ generateImageBin ]
      ++ lib.optionals icfg.actions.checkWeather.enable [ checkWeatherBin ]
      ++ lib.optionals icfg.actions.checkCalendar.enable [ checkCalendarBin ]
      ++ lib.optionals icfg.actions.solveCaptcha.enable [ solveCaptchaBin ]
      ++ lib.optional (icfg.exec.netIsolatedBins != [ ]) offlineLauncher
      ++ icfg.extraPackages;

      users.users.${icfg.user} = {
        isNormalUser = true;
        group = icfg.user;
        home = homeDir;
        createHome = true;
        shell = pkgs.bashInteractive;
        description = "OpenClaw agent";
        # Every agent is a member of `agents`, the group that reads the SHARED
        # service API keys (the image/weather/captcha/TTS tokens). Those are
        # per-SERVICE, not per-agent — a second agent uses the same 2Captcha
        # account — so the secret is group-readable rather than chowned to whichever
        # agent happened to be configured first. Deliberately NOT the `openclaw`
        # group below: that one reads the state TREE, and putting agents in it would
        # let each agent read every other agent's memory and sessions.
        extraGroups = [ "agents" ];
        # Local-only identity: no password, no keys, and sshd refuses it outright
        # (below), so the account can be inhabited from a root session on this box
        # and nowhere else. `!` is an invalid hash — it matches nothing.
        hashedPassword = "!";
        openssh.authorizedKeys.keys = [ ];
      };
      users.groups.${icfg.user} = { };

      # Read access to the agent's service state for principals who should be
      # able to inspect it without becoming the agent. Deliberately NOT the
      # agent's primary group — it owns its files as itself, and this is only an
      # ACL over the state tree. Join it with users.users.<name>.extraGroups.
      users.groups.openclaw = { };

      # Read access to the SHARED service secrets — API keys that belong to a
      # SERVICE, not to an agent (2Captcha, OpenWeatherMap, Gemini, ElevenLabs …).
      # Every agent user joins it (see extraGroups above), so such a secret is
      # granted once with `group = "agents"; mode = "0440";` and every agent —
      # present and future — can read it, with no agent name anywhere in the secret
      # declaration. Agent-IDENTITY secrets (a Telegram bot token and its
      # allowlisted ID) are the opposite case: they stay owned by the one agent they
      # belong to. Named generically because the membership is "is an agent on this
      # host", not "is an OpenClaw instance" — a future non-OpenClaw agent joins the
      # same group and inherits the same key access.
      users.groups.agents = { };

      # Belt and braces on top of the empty password/key set: an authorized_keys
      # file or password added later cannot silently open remote access. Covers
      # mosh too, which authenticates over ssh. Act as the agent with
      # `sudo -u <user> -H ...`.
      services.openssh.settings.DenyUsers = [ icfg.user ];

      # Passwordless sudo for exactly the commands listed in icfg.sudoCommands and
      # nothing else. NOPASSWD is required because the account has no password (`!`
      # above), so it could not answer a prompt even if asked.
      security.sudo.extraRules = lib.mkIf (icfg.sudoCommands != [ ]) [
        {
          users = [ icfg.user ];
          commands = map (command: {
            inherit command;
            options = [ "NOPASSWD" ];
          }) icfg.sudoCommands;
        }
      ];

      # The state dir is the agent's, group-readable by openclaw. setgid so
      # everything written below it inherits that group without the agent having
      # to be a member — with UMask=0027 below, that is what makes the state
      # actually readable to the group rather than just nominally owned by it.
      #
      # The Z line recursively enforces ownership across the whole tree on every
      # activation. The service has changed its running user over its life, which
      # left subdirs (agents/, logs/, devices/) owned by the previous user and
      # unreadable to the current one — the agent then hit EACCES creating session
      # dirs and every Telegram request failed. Mode "-" leaves file modes alone
      # (OpenClaw manages its own 0700 dirs); only uid/gid are re-applied, so this
      # self-heals a user change without fighting the app over permissions.
      systemd.tmpfiles.rules = [
        "d /var/lib/openclaw 0755 root root -"
        "d ${stateDir} 2750 ${icfg.user} openclaw -"
        "Z ${stateDir} - ${icfg.user} openclaw -"
      ];

      # Grant the agent ACL access to icfg.access paths. This is an ACTIVATION
      # SCRIPT, not a oneshot service, and it matters: activation scripts run on
      # EVERY `nixos-rebuild switch` and boot, whereas NixOS only re-runs an
      # unchanged oneshot on reboot — so with a service, a switch would leave a
      # broken grant unrepaired. `deps = [ "users" ]` orders it AFTER the users
      # activation, which chmods home dirs to their homeMode (e.g. /home/alex to
      # 0700) and in doing so recomputes any POSIX ACL mask to `---`, silently
      # neutering a `u:<agent>:X` traversal grant (the entry stays, effective
      # becomes ---). Re-running setfacl here restores both the entry and the
      # mask on every switch. A bad path just logs and does not abort activation.
      system.activationScripts."openclaw-grant-access-${name}" = lib.mkIf (icfg.access != { }) {
        deps = [ "users" ];
        text = lib.concatStrings (
          lib.mapAttrsToList (
            path: opts:
            let
              rec' = lib.optionalString opts.recursive "-R ";
            in
            ''
              ${pkgs.acl}/bin/setfacl ${rec'}-m u:${icfg.user}:${opts.permissions} ${lib.escapeShellArg path} \
                || echo "[openclaw] WARN: setfacl grant failed for ${path}" >&2
            ''
            + lib.optionalString opts.defaultAcl ''
              ${pkgs.acl}/bin/setfacl ${rec'}-d -m u:${icfg.user}:${opts.permissions} ${lib.escapeShellArg path} \
                || echo "[openclaw] WARN: default-ACL grant failed for ${path}" >&2
            ''
          ) icfg.access
        );
      };

      systemd.services."openclaw-${name}" = {
        description = "OpenClaw agent gateway (Telegram-only)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        # `claude` is only on PATH for the claude-cli runtime (subscription auth) —
        # the native runtime (agentRuntime = null) never shells out to it, so it is
        # gated on the backend actually being claude-cli. The rest is what the
        # agent's own shell tooling generally expects. When STT is on, whisper-cli
        # joins the PATH so OpenClaw can exec the configured transcription command
        # by name. (ffmpeg is NOT enough on PATH — OpenClaw resolves it via
        # requireSystemBin/trusted dirs, so it goes in environment.systemPackages
        # below instead.)
        path = [
          pkgs.git
          pkgs.bash
          pkgs.coreutils
          pkgs.jq
          pkgs.ripgrep
        ]
        ++ lib.optionals (icfg.agentRuntime == "claude-cli") [ pkgs.claude-code ]
        ++ lib.optionals icfg.stt.enable [ icfg.stt.package ]
        # Host-supplied tools the agent may invoke by name (still gated by the
        # exec allowlist for whether a run needs approval — see icfg.exec). Also in
        # environment.systemPackages above so the safe-bin trust check honors them.
        ++ icfg.extraPackages;

        environment = {
          HOME = homeDir;
          OPENCLAW_STATE_DIR = stateDir;
          OPENCLAW_CONFIG_PATH = configFile;
        };

        serviceConfig = {
          User = icfg.user;
          Group = icfg.user;

          # Config seeding is a BLUEPRINT merge, not a hard overwrite, in three
          # steps: (1) apply the config blueprint, (2) patch in the Telegram
          # allowlist from the secret file, (3) union the exec-approval globs into
          # the agent's live allowlist with a single jq merge. Step 3 was formerly
          # ~34 sequential `openclaw approvals allowlist add` calls (~1.4s of Node
          # cold-start each) that overran the 90s start-pre timeout and crash-
          # looped the gateway; it is now one Node-free jq call (regression fixed
          # 2026-07-26).
          #
          # (1) First boot (file absent) lays down the full Nix-rendered config,
          # created fresh inside the setgid state dir so it lands in the openclaw
          # group. Every subsequent start recursively patches the Nix-declared keys
          # back on top of whatever the agent has written — so declared keys (incl.
          # the enforced security keys) are re-asserted, while keys Nix does NOT
          # declare survive as the agent's own. A corrupt existing file / failed
          # merge falls back to a clean reseed so the gateway always starts valid.
          #
          # (2) Patch the allowlisted Telegram ID(s) in from the runtime secret
          # file (one ID per line; blanks and #comments ignored). The blueprint
          # wrote the allowlist FAIL-CLOSED (empty), so THIS is what opens access —
          # and only to these IDs, re-asserted every start. A missing/empty/
          # unreadable file leaves the allowlist empty, so the bot answers no one.
          ExecStartPre = pkgs.writeShellScript "openclaw-seed-config" ''
            set -euo pipefail

            # (0) Materialise the module skills into a writable, hardlink-free tree
            # (see skillsStageSeed) BEFORE the gateway starts, so the loader accepts
            # them. No-op when the instance ships no skills.
            ${skillsStageSeed}

            # (0b) Rebuild the OpenPGP keyring from nix (see gpgSeed), so the agent
            # starts from exactly the keys this module declares and nothing it may
            # have imported since. No-op unless mail.gpg is on.
            ${gpgSeed}
            tmpl=${configTemplate}
            if [ -f ${configFile} ]; then
              ${lib.getExe openclawPatched} config patch --file "$tmpl" || {
                rm -f ${configFile}
                install -m 0640 "$tmpl" ${configFile}
              }
            else
              install -m 0640 "$tmpl" ${configFile}
            fi

            ids=""
            if [ -r ${lib.escapeShellArg icfg.telegram.allowedIdFile} ]; then
              while IFS= read -r line || [ -n "$line" ]; do
                line=''${line//[[:space:]]/}
                [ -z "$line" ] && continue
                case "$line" in \#*) continue ;; esac
                ids="$ids''${ids:+,}\"$line\""
              done < ${lib.escapeShellArg icfg.telegram.allowedIdFile}
            fi
            if [ -z "$ids" ]; then
              echo "[openclaw] WARN: no Telegram ID in ${icfg.telegram.allowedIdFile}; allowlist stays empty (bot answers no one)" >&2
            fi
            printf '{"channels":{"telegram":{"allowFrom":[%s]}},"commands":{"ownerAllowFrom":[%s]}}' "$ids" "$ids" \
              | ${lib.getExe openclawPatched} config patch --stdin

            # (3) Seed the operator-declared exec-approval globs (single jq merge).
            ${allowlistSeedMerge}
          '';
          ExecStart = "${lib.getExe openclawPatched} gateway";
          Restart = "on-failure";
          RestartSec = 5;
          # The seed above is now two fast config patches plus one jq merge, but
          # keep a margin over systemd's 90s default so a momentarily loaded box
          # never times the gateway out before it binds.
          TimeoutStartSec = 180;

          LoadCredential = [
            "telegram-token:${icfg.telegram.tokenFile}"
          ]
          # systemd reads the key as root and exposes it 0400 to the service user,
          # so the secret never depends on the sops/agenix file's own ownership
          # being right — same handling the bot token already gets.
          ++ lib.optional (gpgEnabled && gpgCfg.secretKeyFile != null) "mail-gpg-key:${gpgCfg.secretKeyFile}";

          # Extra env for provider API keys (Gemini fallback, ElevenLabs TTS, …),
          # supplied as files from outside the module. Empty by default.
          EnvironmentFile = icfg.environmentFiles;

          # No StateDirectory=: systemd would chown the tree to User:Group, i.e.
          # the agent's own group, and there is no way to ask it for a different
          # group. tmpfiles owns the directory instead (see above).
          WorkingDirectory = stateDir;
          # 0640 files / 0750 dirs, so the openclaw group can read what the agent
          # writes below the state dir. Its home stays 0700 regardless.
          UMask = "0027";
        };
      };
    };

  enabledInstances = lib.filterAttrs (_: i: i.enable) cfg.instances;

  instanceModule = { name, ... }: {
    options = {
      # Whether this agent instance is enabled. Disabling one leaves the other
      # agents untouched; an enabled instance is what creates its OS user, home,
      # state dir and gateway service.
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this OpenClaw agent instance is enabled.";
      };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        example = lib.literalExpression "[ pkgs.ffmpeg pkgs.pandoc ]";
        description = ''
          Extra packages the agent can resolve BY NAME when it runs a command.
          Placed on BOTH the service `path` (so `bash -c` resolves them) AND
          environment.systemPackages (so OpenClaw's safe-bin trust check, which does
          NOT auto-trust PATH, honors them when allowlisted). This is purely a "make
          the binary reachable" grant — it does NOT by itself bless anything to run
          unprompted. Whether a given invocation runs without an approval prompt is
          still decided entirely by `exec.safeBins` / `exec.allowlist` under
          `exec.security = "allowlist"`. Use this for tools the agent should be able
          to invoke — media/document converters, interpreters, etc. — kept in the
          host config so the module stays deployment-agnostic.
        '';
      };

      toolkit = lib.mkOption {
        type = lib.types.submodule {
          options = {
            python = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Python libraries pre-installed in the agent's interpreter.";
            };
            r = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "R packages pre-installed in the agent's R.";
            };
            cli = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Notable CLI tools on the agent's PATH worth advertising.";
            };
            notes = lib.mkOption {
              type = lib.types.lines;
              default = "";
              description = "Free-form guidance appended to the skill (import-name gotchas, GPU caveats, …).";
            };
          };
        };
        default = { };
        description = ''
          Inventory of pre-installed tooling, rendered into a `toolkit` SKILL.md so
          the agent KNOWS what it already has. Installing a package (via
          extraPackages / the interpreter wrappers) grants a capability but does NOT
          tell the agent it exists, and the env is a closed Nix closure it cannot
          extend at runtime (no pip / install.packages) — so without this it guesses,
          and a wrong guess wastes an approval prompt. Purely informational: it does
          NOT bless anything to run unprompted; the exec policy still decides that.
          Derive the lists from the same package sets you install (e.g.
          `map (p: p.pname) (pyPkgs python3Packages)`) so the skill cannot drift out of
          sync with what is actually present. Leave every field empty to skip the skill.
        '';
      };

      projects = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Render the `projects` SKILL.md for this instance.";
            };
          };
        };
        default = { };
        description = ''
          Teach the agent the Python/R project convention: inside a repository that
          declares its own environment, use THAT environment (`.envrc` + direnv,
          `use nix`, a uv virtualenv) rather than the agent's own baked interpreters,
          and never install into a global or user-wide library. The skill also draws
          the opposite line — for ad-hoc scratch work in its workspace it should just
          use the interpreters from `extraPackages`, not bootstrap a virtualenv for a
          five-line script.

          Purely informational, like `toolkit`: it does NOT bless anything to run
          unprompted. Only enable it for an instance that can actually ACT on it —
          `direnv` and `uv` reachable via extraPackages, `rix` in its R library, and a
          project tree it may write to. Enabling it without the tooling just tells the
          agent to run commands it does not have.
        '';
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = ''
          Account the agent lives as — a normal user with a home at /home/<user>,
          holding its workspace and its Claude CLI login. Override it with the
          bot's own name, so the identity it acts under on this host matches the
          one people talk to. It gets no password and no SSH keys, so it is not
          reachable from outside; use `sudo -u <user> -H ...` to act as it.
        '';
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "anthropic/claude-sonnet-4-6";
        description = "Primary model, as provider/model.";
      };

      fallbackModels = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "anthropic/claude-opus-4-8" ];
        description = ''
          Ordered failover models (each as provider/model) tried in turn when the
          primary model errors. This is failover, NOT on-demand escalation: a more
          powerful model here runs only when the primary call fails, not because a
          task looks hard. Defaults to Opus 4.8 behind the Sonnet 4.6 primary — the
          strong model catches outages/rate-limits on the everyday one. Set to [ ]
          to disable fallbacks.
        '';
      };

      environmentFiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = lib.literalExpression ''
          [
            "-/run/secrets/openclaw-gemini-env"   # GEMINI_API_KEY for a google/* fallback
            "/run/secrets/openclaw-elevenlabs-env" # ELEVENLABS_API_KEY for TTS
          ]
        '';
        description = ''
          Extra systemd EnvironmentFile paths for the service — the place to supply
          provider API keys the agent needs, so a token comes in from OUTSIDE the
          module just like the model it belongs to: a google/* fallbackModel needs
          GEMINI_API_KEY, an elevenlabs TTS voice needs ELEVENLABS_API_KEY, etc.
          Kept as plain paths so the module stays agnostic about the secret system;
          prefix a path with "-" to make it optional (a missing file won't fail
          start). These are read only at runtime, never as Nix values, so no key
          enters the store or the config.
        '';
      };

      agentRuntime = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "claude-cli";
        example = null;
        description = ''
          Execution backend for the agent. "claude-cli" reuses this host's Claude
          Code CLI login, so the Claude subscription pays rather than an Anthropic
          API key. Set to null to use the provider's own API auth instead (which
          then needs an API key configured out of band).
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 18789;
        description = ''
          Loopback port for the gateway / control UI. Bound to 127.0.0.1 only —
          never opened in the firewall. Reach it locally (e.g. via SSH tunnel).
        '';
      };

      heartbeat = {
        enable = lib.mkEnableOption ''
          periodic autonomous "heartbeat" turns — the agent wakes on a fixed
          cadence (optionally bounded to active hours) to do proactive work'';

        every = lib.mkOption {
          type = lib.types.str;
          default = "2h";
          example = "30m";
          description = ''
            Heartbeat cadence as a duration string (maps to
            agents.defaults.heartbeat.every), e.g. "2h", "90m". How often a
            heartbeat turn fires while within activeHours.
          '';
        };

        activeHours = {
          start = lib.mkOption {
            type = lib.types.str;
            default = "08:00";
            description = "Local time-of-day (HH:MM) at which heartbeats begin firing.";
          };
          end = lib.mkOption {
            type = lib.types.str;
            default = "22:00";
            description = "Local time-of-day (HH:MM) after which heartbeats stop firing.";
          };
          timezone = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "Europe/Madrid";
            description = ''
              IANA timezone the activeHours window is interpreted in. Null lets
              OpenClaw use its own default; set it to the host timezone so the
              window means local wall-clock time regardless of the process TZ.
            '';
          };
        };
      };

      telegram = {
        # Both inputs are secrets and this repo is public, so the module takes
        # runtime FILE PATHS rather than the values — and it is agnostic about what
        # produces those files. Point them at sops-nix (config.sops.secrets.<x>.path),
        # agenix, or any out-of-band file; the module only ever reads them at run
        # time, never at eval, so the secrets never enter the store or the repo.
        # NB: use str, not path — a `path` value would copy the secret INTO the
        # store, which is exactly what we are avoiding.
        tokenFile = lib.mkOption {
          type = lib.types.str;
          example = "/run/secrets/openclaw-telegram-token";
          description = ''
            Path to a file containing the BotFather bot token (single line). Loaded
            as a systemd credential and referenced by channels.telegram.tokenFile;
            it is never read at eval time, so it never lands in the store or repo.
          '';
        };
        allowedIdFile = lib.mkOption {
          type = lib.types.str;
          example = "/run/secrets/openclaw-telegram-userid";
          description = ''
            Path to a file containing the numeric Telegram user ID(s) allowlisted
            for DMs and command ownership — one ID per line (blank lines and lines
            starting with `#` are ignored). Read at service START and patched into
            the config's allowlist; if the file is missing or empty the allowlist
            stays empty and the bot answers no one (fail-closed). Get your ID from
            @userinfobot.
          '';
        };
      };

      tts = {
        # Reply text-to-speech, modelled as options rather than a raw settings blob
        # so voice/provider/etc. are configured from outside the module. Assembled
        # into messages.tts (see defaultConfig). The provider API key is never a
        # Nix value — it is read from the service environment (e.g. wire an
        # EnvironmentFile setting ELEVENLABS_API_KEY on the host).
        enable = lib.mkEnableOption "reply text-to-speech";
        provider = lib.mkOption {
          type = lib.types.str;
          default = "elevenlabs";
          description = ''
            TTS provider id (e.g. "elevenlabs", "microsoft"). The voiceId/modelId
            below are placed under this provider in the reply persona.
          '';
        };
        voiceId = lib.mkOption {
          type = lib.types.str;
          example = "dNjJKg63Fr5AXwIdkATa";
          description = ''
            Provider voice identifier for replies (for ElevenLabs, the voice ID).
          '';
        };
        modelId = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "eleven_multilingual_v2";
          description = ''
            Provider TTS model id, or null to leave it to the provider default.
            ElevenLabs "eleven_multilingual_v2" handles non-English (e.g. Spanish);
            "eleven_turbo_v2_5" trades some quality for latency.
          '';
        };
        speed = lib.mkOption {
          type = lib.types.nullOr (lib.types.numbers.between 0.5 2.0);
          default = null;
          example = 1.1;
          description = ''
            Speech rate for replies, or null for the provider default. Maps to the
            ElevenLabs voice setting `voiceSettings.speed` (accepted range
            0.5–2.0; 1.0 is normal, >1 faster). ElevenLabs-specific; other
            providers model rate differently.
          '';
        };
        auto = lib.mkOption {
          type = lib.types.enum [
            "off"
            "always"
            "inbound"
            "tagged"
          ];
          default = "inbound";
          description = ''
            When to speak. "inbound" = only reply with voice when the user sent a
            voice message (talk→talk); "always" speaks every reply; "tagged" only
            when explicitly requested; "off" disables auto-speech.
          '';
        };
        mode = lib.mkOption {
          type = lib.types.enum [
            "final"
            "all"
          ];
          default = "final";
          description = "Synthesize only the final reply (\"final\") or every streamed chunk (\"all\").";
        };
        label = lib.mkOption {
          type = lib.types.str;
          default = "default";
          description = "Human label for the reply TTS persona.";
        };
        maxTextLength = lib.mkOption {
          type = lib.types.ints.positive;
          default = 800;
          description = "Cap on characters synthesized per reply, so a huge message can't spawn a giant/slow render.";
        };
        timeoutMs = lib.mkOption {
          type = lib.types.ints.positive;
          default = 15000;
          description = "Synthesis timeout in milliseconds.";
        };
      };

      # Inbound speech-to-text (voice notes -> text the agent can read). Modelled
      # as options because the claude-cli runtime can't ingest audio itself, so a
      # local transcriber is the self-contained way to make voice messages work.
      stt = {
        enable = lib.mkEnableOption ''
          inbound speech-to-text so eva understands voice messages. Wires a
          whisper.cpp CLI entry into tools.media.audio and puts whisper-cli +
          ffmpeg on the service PATH. OpenClaw transcodes the inbound OGG/Opus to
          16 kHz WAV and reads whisper's .txt output; the transcript is handed to
          the agent like a typed message. Needs stt.model set'';
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.whisper-cpp;
          defaultText = lib.literalExpression "pkgs.whisper-cpp";
          description = "whisper.cpp package providing the `whisper-cli` binary.";
        };
        model = lib.mkOption {
          type = lib.types.path;
          example = lib.literalExpression ''
            pkgs.fetchurl {
              url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
              hash = "sha256-...";
            }'';
          description = ''
            GGML whisper model file used to transcribe voice notes. Supplied from
            OUTSIDE the module (e.g. a fetchurl), so no hash is baked in here.
            Multilingual models (ggml-small/medium/…) handle Spanish; larger =
            more accurate but slower on CPU.
          '';
        };
        language = lib.mkOption {
          type = lib.types.str;
          default = "auto";
          example = "es";
          description = ''
            whisper `-l` language: an ISO code like "es" to pin the language, or
            "auto" to detect per clip (handles a Spanish/English mix).
          '';
        };
        timeoutSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 300;
          description = "Max seconds for a single transcription before it is aborted.";
        };
      };

      # Semantic memory search (vector recall over MEMORY.md + memory/*.md).
      # Modelled as options because the embedding backend is a real choice with a
      # cost/privacy/keys tradeoff: openclaw's own default provider is "openai"
      # (needs an API key), so a host that keeps no keys must opt into a local
      # embedder or wire a remote key deliberately. Assembles
      # agents.defaults.memorySearch.
      memorySearch = {
        enable = lib.mkEnableOption ''
          semantic memory search. When off, the agent still has its memory FILES
          (MEMORY.md + memory/*.md) — only vector recall is disabled. When on, an
          embedding backend is required (see `provider`); reindex with
          `openclaw memory index --force`'';
        provider = lib.mkOption {
          type = lib.types.str;
          default = "local";
          example = "voyage";
          description = ''
            Embedding backend (maps to agents.defaults.memorySearch.provider).
            "local" runs a GGUF model on-box via node-llama-cpp — keyless, no
            per-token cost, and memory text never leaves the host — and needs
            `localModelPath`. Remote providers ("openai", "voyage", "gemini",
            "mistral", "ollama", "lmstudio", …) instead need their API key in the
            service environment (see `environmentFiles`) and optionally a `model`
            name. openclaw's own default is "openai"; this module defaults to
            "local" so memory search works with no keys out of the box.
          '';
        };
        localModelPath = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = lib.literalExpression ''
            pkgs.fetchurl {
              url = "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf";
              hash = "sha256-...";
            }'';
          description = ''
            GGUF embedding model file for `provider = "local"`, supplied from OUTSIDE
            the module (e.g. a fetchurl) so no model is baked into the generic module
            — the same pattern as `stt.model`. Maps to
            agents.defaults.memorySearch.local.modelPath. Ignored by remote
            providers. A small model (e.g. nomic-embed-text v1.5 Q4_K_M, ~84MB) is
            CPU-friendly; pick a multilingual model if recall in other languages
            matters. Required when `provider = "local"` and `enable` is set.
          '';
        };
        model = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "voyage-3-lite";
          description = ''
            Embedding model NAME override for a REMOTE provider (maps to
            agents.defaults.memorySearch.model). Null uses the provider default. Not
            used by `provider = "local"` — that takes `localModelPath` instead.
          '';
        };
      };

      settings = lib.mkOption {
        type = settingsFormat.type;
        default = { };
        example = lib.literalExpression ''
          {
            agents.defaults.model.primary = "anthropic/claude-opus-4-8";
            # extra skill directories loaded alongside the workspace
            skills.load.extraDirs = [ "/etc/openclaw/skills" ];
            # register an MCP tool server
            mcp.servers.fetch.command = "''${pkgs.mcp-fetch}/bin/mcp-fetch";
            # widen/narrow the agent's tool + exec policy
            tools.alsoAllow = [ "web.search" ];
          }
        '';
        description = ''
          Declarative OpenClaw configuration, deep-merged into openclaw.json. This
          is a BLUEPRINT, not a hard overwrite: first boot writes the full config,
          and every start thereafter recursively patches the keys declared here
          back on top of whatever the agent has written. So anything set here
          always wins (it is re-asserted each start), while keys NOT declared here
          are the agent's own and persist across restarts — `openclaw config set`
          / runtime writes to undeclared keys stick. Run `openclaw config schema`
          to see the full key set.

          Precedence within the blueprint: module defaults < this < enforced
          security keys. The security-critical keys (gateway.bind/mode, the
          Telegram allowlist, dmPolicy/groupPolicy, ownerAllowFrom) are forced on
          top and re-patched every start, so a mistaken value here — or anything
          the agent writes at runtime — cannot durably open access.

          Note: agent *skills* live in the workspace (and any skills.load.extraDirs
          above) and persist independently of this file.
        '';
      };

      mail = {
        enable = lib.mkEnableOption "email for the agent: read its own Maildir, plus a constrained, recipient-gated `send-email` helper";

        manageMaildir = lib.mkEnableOption ''
          LOCAL Maildir mutation in the unprompted allowlist so the agent can
          organise its OWN mailbox — mark read/flagged, move messages between
          folders, create folders, incorporate/deliver mail (mflag/mrefile/mmkdir/
          minc/mdeliver). These only touch the local Maildir; they never send or
          fetch over the network, so the compose/send tools (mcom/mrep/mfwd/…) and
          msed stay gated, and the only blessed outbound path remains the
          recipient-gated send-email helper. Requires mail.enable'';

        fromAddress = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "e.lebbot@example.com";
          description = ''
            Optional sender identity. When set, the generated `send-email` helper
            forces it as the envelope sender (via a nix-pinned wrapper), so the
            agent can only ever send as this address; when null, the system default
            (Postfix myorigin) is used. The address is a nix parameter — it is NOT
            baked into the action script; actions/send-email stays generic.

            Inbound delivery to the agent's ~/Maildir is arranged separately (an
            MX/alias pointing here); this option only concerns outbound identity,
            tooling and the skill.
          '';
        };

        unpromptedRecipients = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "me@example.com" ];
          description = ''
            Recipient addresses the agent may email WITHOUT an approval prompt, one
            recipient per send. Each becomes an exact exec-allowlist rule
            (`send-email <addr>`). Any other recipient — or more than one recipient
            in a single send — does not match and falls through to the exec `ask`
            gate, so the owner approves it in the origin channel. This is the data-
            exfiltration guard: a prompt-injected agent cannot silently mail data to
            an arbitrary address. Empty (default) gates every send.
          '';
        };

        # --- confidential mail (OpenPGP) -------------------------------------
        # Closes a REAL leak: inbound reaches this box through an external
        # forwarder and outbound leaves through a relay, so both see the full
        # plaintext of every message today. End-to-end encryption removes them
        # from the trust set, and a signature authenticates the owner end-to-end
        # rather than depending on DMARC surviving the forwarding hop.
        #
        # What it deliberately does NOT do: protect anything from the AGENT. The
        # secret key has to live where the agent can use it, so a compromised or
        # prompt-injected agent reads everything it could read anyway — the
        # exfiltration guard remains the recipient allowlist, not the crypto. Nor
        # does it hide content from the model provider: the agent decrypts in
        # order to reason, so the plaintext reaches the API either way, and (by
        # the owner's explicit choice) decrypted content may persist in cleartext
        # in the agent's own files.
        gpg = {
          enable = lib.mkEnableOption ''
            confidential mail: a `decrypt-mail` reader and an always-encrypting
            `send-encrypted-mail` sender, both against a CLOSED keyring rebuilt
            from nix on every start (no keyserver, no opportunistic import).
            Requires mail.enable, and `keys` to name at least one owner key.

            Note that raw `gpg` is deliberately NOT put on the agent's PATH or in
            safeBins — it is a general-purpose crypto, file and network tool
            (`--recv-keys`, `--export-secret-keys`, sign-anything), which is
            exactly the shape this module gates elsewhere for curl and sendmail.
            The two wrappers below are the whole OpenPGP surface the agent gets'';

          secretKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "/run/secrets/openclaw-eva-gpg-key";
            description = ''
              Path to the agent's OWN exported secret key (armored or binary),
              read at RUNTIME as a systemd credential — like telegram.tokenFile it
              is a `str` path, not a `path`, so the key never enters the nix store
              or this repo. Point it at a sops-nix secret, an agenix file, or any
              out-of-band file.

              The key MUST be passphrase-less. A passphrase the agent has to
              supply from a file sitting next to the key protects nothing, and a
              passphrase it cannot supply means it cannot decrypt its own mail.

              Generate once, out of band, then import the secret half here and
              publish the public half to whoever writes to the agent:

                gpg --quick-generate-key 'Eva <e.nebot@example.com>' default default never
                gpg --export-secret-keys --armor <fpr>   # -> the sops secret
                gpg --export --armor <fpr>               # -> your own keyring

              When null (or unreadable at start) the keyring is built without a
              secret key: decryption and signing fail closed, and nothing is sent
              in cleartext as a fallback.
            '';
          };

          fingerprint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "9E1A2B3C4D5E6F708192A3B4C5D6E7F809A1B2C3";
            description = ''
              Optional full fingerprint of the agent's own key, pinning WHICH key
              signs outgoing mail (`--local-user <fpr>!`). A fingerprint is public,
              so unlike the key itself it is fine in nix. When null, gpg picks the
              default secret key — which is unambiguous in practice, since the
              keyring is rebuilt from nix each start and holds exactly the one
              secret key imported from secretKeyFile.
            '';
          };

          keys = lib.mkOption {
            default = [ ];
            example = [
              {
                address = "me@example.com";
                fingerprint = "9E1A2B3C4D5E6F708192A3B4C5D6E7F809A1B2C3";
                publicKeyFile = "/etc/nixos/keys/me.asc";
              }
            ];
            description = ''
              The owner keys the agent knows about. Each entry does double duty:
              its fingerprint is a trusted SIGNER for inbound mail (reported by
              `decrypt-mail`), and an encryption target for outbound mail to
              `address`.

              Encryption is decided HERE, per recipient, and never by the agent per
              message: listing an address makes encrypted mail to it the only
              option — `send-email`/`send-trusted-mail` refuse it outright (see
              requireEncryption). A mode the agent elects is not a boundary, since
              whatever can talk it into "confidential" can talk it back out.
            '';
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  address = lib.mkOption {
                    type = lib.types.str;
                    example = "me@example.com";
                    description = "Recipient address this key belongs to (matched case-insensitively).";
                  };
                  fingerprint = lib.mkOption {
                    type = lib.types.str;
                    example = "9E1A2B3C4D5E6F708192A3B4C5D6E7F809A1B2C3";
                    description = ''
                      Full 40-hex OpenPGP fingerprint, no spaces. Mail is encrypted
                      to this fingerprint rather than to the address, so a key
                      imported at runtime cannot be substituted for the pinned one;
                      inbound signatures are checked against it too.
                    '';
                  };
                  publicKeyFile = lib.mkOption {
                    type = lib.types.path;
                    example = "/etc/nixos/keys/me.asc";
                    description = ''
                      Exported PUBLIC key, imported into the agent's keyring at
                      every start. A `path` (unlike secretKeyFile) because a public
                      key is public — the store is a fine home for it.
                    '';
                  };
                  requireEncryption = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = ''
                      Whether mail to `address` MUST be encrypted. True (the
                      default) is fail-closed: the plaintext senders refuse this
                      recipient, so if OpenPGP breaks the agent cannot reach them at
                      all rather than quietly falling back to cleartext — which is
                      the point of the design, and worth being deliberate about.

                      Set false to keep the key for signature verification and
                      optional encryption while leaving plaintext allowed. Still an
                      operator decision pinned in nix, not an agent-facing switch.
                    '';
                  };
                };
              }
            );
          };
        };
      };

      # Sanctioned, SELF-GATING action wrappers. Each is an immutable script that
      # constrains its OWN destination (host / recipient) to a nix-pinned trusted
      # set and refuses anything else, so it is safe to run unprompted — the safe,
      # constrained way to hand the agent an outbound capability whose destination
      # (unlike a raw curl or sendmail) cannot be repointed by a prompt injection.
      actions = {
        requestUrl = {
          enable = lib.mkEnableOption ''
            the `request-trusted-url` action: constrained web GET/HEAD limited to
            the hosts in `trustedSites`. This is the sanctioned replacement for the
            disabled ungated web_fetch — raw curl/wget stay gated'';
          trustedSites = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [
              "*.example.com"
              "docs.example.org"
            ];
            description = ''
              Shell globs matched against the URL host (case-insensitive, userinfo
              stripped so `trusted@evil` cannot spoof it). A request to any host not
              matching one of these is refused. Pinned into the wrapper, so the
              agent cannot widen the set at runtime. `*.example.com` matches
              subdomains only, not the apex — list the apex explicitly if needed.
            '';
          };
        };
        trustedMail = {
          enable = lib.mkEnableOption ''
            the `send-trusted-mail` action: send to recipients in `trustedAddresses`
            only, refusing any other recipient outright (unlike the generic
            send-email, which falls through to an approval prompt)'';
          trustedAddresses = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "me@example.com" ];
            description = ''
              Exact recipient addresses (case-insensitive) the wrapper will deliver
              to. Any other recipient is refused. Uses `mail.fromAddress` as the
              envelope sender. Pinned into the wrapper, so the trusted set cannot be
              widened at runtime.
            '';
          };
        };
        generateImage = {
          enable = lib.mkEnableOption ''
            the `generate-image` action: image generation via a Gemini-compatible
            `generateContent` endpoint. The model, token file, optional reference
            image and endpoint are all nix-pinned, so it is destination-fixed and
            safe to bless whole-binary; the agent only supplies the prompt and the
            output path. Needs `tokenFile` set'';
          model = lib.mkOption {
            type = lib.types.str;
            default = "gemini-2.5-flash-image";
            example = "gemini-2.5-flash-image";
            description = ''
              Image model id passed to `<apiBase>/models/<model>:generateContent`.
            '';
          };
          tokenFile = lib.mkOption {
            type = lib.types.str;
            example = "/run/secrets/openclaw-gemini-token";
            description = ''
              Path to a file holding the API key (single line), read at RUNTIME —
              like telegram.tokenFile, it is a `str` path (not a `path`) so the key
              never enters the store or this public repo. Point it at a sops-nix
              secret, an agenix file, or any out-of-band file the agent can read.
            '';
          };
          referenceImage = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "/var/lib/openclaw/avatars/reference.png";
            description = ''
              Optional DEFAULT reference image, used when the caller passes no
              `--reference` (and did not pass `--no-reference`). The agent can
              override it per call with `--reference <img>` or drop it with
              `--no-reference`, and can also run prompt-only. Null means no default
              (prompt-only unless a reference is given). A runtime path string.
            '';
          };
          referenceRoot = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "/var/lib/openclaw/workspace";
            description = ''
              Optional directory that a runtime `--reference` must resolve under.
              When set, the agent may only reference images inside this tree (so it
              can pick among its own images but cannot feed an arbitrary file — e.g.
              a secret — to the endpoint). Null leaves `--reference` unconstrained
              (any readable image), which is fine for a trusted/uncontested host but
              widens the input surface. Does not affect `referenceImage` (the pinned
              default), which is always allowed.
            '';
          };
          apiBase = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "https://generativelanguage.googleapis.com/v1beta";
            description = ''
              Override the API base URL (default: Google Generative Language
              v1beta). Set this to target a compatible endpoint. NB: whatever host
              this resolves to must also be reachable — the wrapper uses raw curl,
              not request-trusted-url, so it is not bound by trustedSites.
            '';
          };
        };
        checkWeather = {
          enable = lib.mkEnableOption ''
            the `check-weather` action: current weather via the OpenWeatherMap API.
            Destination-fixed, so it is blessed whole-binary. Needs `tokenFile` set'';
          tokenFile = lib.mkOption {
            type = lib.types.str;
            example = "/run/secrets/openclaw-openweather-token";
            description = ''
              Path to a file holding the OpenWeatherMap API key (single line), read
              at RUNTIME — a `str` path (not a `path`), so the key never enters the
              store or this public repo. Point it at a sops-nix secret or any
              out-of-band file the agent can read.
            '';
          };
          units = lib.mkOption {
            type = lib.types.enum [
              "standard"
              "metric"
              "imperial"
            ];
            default = "metric";
            description = ''
              Units for temperature/wind: "standard" (K, m/s), "metric" (°C, m/s),
              or "imperial" (°F, mph). Maps to the OpenWeatherMap `units` parameter.
            '';
          };
          lang = lib.mkOption {
            type = lib.types.str;
            default = "en";
            example = "es";
            description = ''
              Response language (OpenWeatherMap `lang`), which localizes the weather
              `description`. An ISO code like "es", "en", "ca", …
            '';
          };
          defaultLocation = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "Barcelona,ES";
            description = ''
              Place query used when the agent gives no location and no coordinates,
              e.g. "Barcelona,ES". Null means a location (or --lat/--lon) is always
              required.
            '';
          };
          apiBase = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "https://api.openweathermap.org/data/2.5";
            description = ''
              Override the API base URL (default OpenWeatherMap data/2.5). The
              wrapper uses raw curl, so whatever host this resolves to must be
              reachable; it is not bound by trustedSites.
            '';
          };
        };
        solveCaptcha = {
          enable = lib.mkEnableOption ''
            the `solve-captcha` action: solve a CAPTCHA blocking a page the agent is
            working on (reCAPTCHA v2/v3, hCaptcha, Turnstile, FunCaptcha, or a plain
            image captcha) through the 2Captcha API, printing the solution token.
            Destination-fixed to the configured endpoint and self-gating on the page
            host, so it is blessed whole-binary; it also ships a `solve-captcha` skill
            with the token-planting workflow. Needs `tokenFile` set.

            Two things keep this from becoming an outbound channel: the wrapper builds
            the task JSON itself from flags, so only the "…Proxyless" task types are
            reachable (no proxy/User-Agent/cookie fields — the solving farm cannot be
            used as a relay), and the page URL must match `allowedSites`. Note the
            capability itself is anti-anti-automation and costs real money per solve:
            keep `allowedSites` to the pages the agent is actually meant to drive'';
          tokenFile = lib.mkOption {
            type = lib.types.str;
            example = "/run/secrets/openclaw-2captcha-token";
            description = ''
              Path to a file holding the 2Captcha API key (single line), read at
              RUNTIME — a `str` path (not a `path`), so the key never enters the store
              or this public repo. Point it at a sops-nix secret or any out-of-band
              file the agent can read.
            '';
          };
          allowedSites = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "docs.google.com" ];
            description = ''
              Shell globs matched against the host of the `--url` (the page the
              captcha sits on), with the same parse as
              `actions.requestUrl.trustedSites`: case-insensitive, userinfo stripped,
              so `trusted.com@evil.com` is tested as evil.com. A captcha on any other
              page is refused. EMPTY (the default) means NO host restriction — set it,
              normally to the hosts the agent's browser may navigate to
              (`settings.browser.ssrfPolicy.hostnameAllowlist`), so a prompt-injected
              agent cannot spend the owner's credit solving captchas elsewhere.
            '';
          };
          imageRoot = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "/home/eva";
            description = ''
              Directory an image-captcha FILE must resolve under, so a screenshot of a
              captcha can be solved but an out-of-tree file (a secret, someone else's
              document) cannot be uploaded to the solving service. Null falls back to
              the agent's $HOME at runtime — a boundary without a nix-hardcoded path,
              same as `generateImage.referenceRoot`.
            '';
          };
          timeoutSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 180;
            description = ''
              How long to wait for a solution before giving up. A reCAPTCHA typically
              comes back in 10–60s; overridable per call with `--timeout`.
            '';
          };
          pollIntervalSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 5;
            description = "Seconds between result polls (also the delay before the first poll).";
          };
          softId = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "1234";
            description = ''
              Optional 2Captcha `softId` (developer/software id) sent with each task.
              Null omits it.
            '';
          };
          apiBase = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "https://api.2captcha.com";
            description = ''
              Override the API base URL (default https://api.2captcha.com). Set this to
              target an API-compatible service (e.g. a rucaptcha/anti-captcha-style
              endpoint). The wrapper uses raw curl, so whatever host this resolves to
              must be reachable; it is not bound by trustedSites.
            '';
          };
        };
        checkCalendar = {
          enable = lib.mkEnableOption ''
            the `check-calendar` action: list upcoming events from an .ics
            calendar. It takes the SOURCE directly — an https:// URL (fetched by
            delegating to `request-trusted-url`, so the fetch inherits the same
            trusted-host allowlist / GET-only / no-redirect policy — the calendar
            host must be an EXACT trusted site, e.g. `calendar.google.com`, not
            `*.google.com`), or a local .ics file / stdin (parsed offline). It
            expands recurrences (RRULE) to real occurrences. Blessed whole-binary:
            local parsing is network-free and the only outbound path is the
            already-hardened request-trusted-url. Collapses the old
            `request-trusted-url <url> | parse-ics` pipe into one command. Needs
            `python3` with `icalendar` + `recurring-ical-events`, pulled in
            automatically'';
        };
      };

      # WHAT IT CAN DO TO THE HOST. The options below are the deliberate, narrow
      # exceptions to the "no host access" posture described in the header: the
      # shell-exec policy, plus ways to hand the agent specific files and specific
      # root commands, and nothing more. All are prompt-injectable surface — grant
      # the minimum.

      exec = {
        # Shell-exec policy. These map to tools.exec.* and are pinned in the
        # enforced config layer (re-asserted every start), so the agent cannot
        # relax them at runtime; the host tunes them here. Everyday chat is
        # unaffected — this only gates the exec (shell) tool.
        security = lib.mkOption {
          type = lib.types.enum [
            "deny"
            "allowlist"
            "full"
          ];
          default = "allowlist";
          description = ''
            Exec security posture. "deny" blocks the shell tool entirely,
            "allowlist" runs only allowlisted commands unprompted (everything else
            is a miss, gated by `ask`), and "full" runs anything without gating.
            Keep "allowlist" for a prompt-injectable agent.
          '';
        };
        ask = lib.mkOption {
          type = lib.types.enum [
            "off"
            "on-miss"
            "always"
          ];
          default = "on-miss";
          description = ''
            When to ask for human confirmation before running an exec command.
            "on-miss" prompts for anything not on the allowlist (`safeBins` plus
            the per-agent runtime allowlist), "always" prompts for everything, and
            "off" never prompts. The prompt surfaces in the originating channel
            (e.g. the Telegram DM) and is answered inline.
          '';
        };
        strictInlineEval = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Require explicit approval for interpreter inline-eval forms (`python
            -c`, `node -e`, `ruby -e`, `osascript -e`), even if the interpreter is
            otherwise allowlisted — so an allowed interpreter cannot smuggle
            arbitrary code past the gate. Leave on unless it is too much friction.
          '';
        };
        safeBins = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = defaultSafeBins;
          description = ''
            Binaries allowed to run WITHOUT an explicit per-agent allowlist entry
            under `security = "allowlist"` — the declarative "what's safe to run"
            list. Defaults to a conservative read-only set; the host replaces or
            extends it (e.g. `safeBins = options.my.openclaw.exec.safeBins.default
            ++ [ "Rscript" ];`). Pinned authoritatively, so the agent cannot add to
            it at runtime. For arg/flag-level constraints on a binary, use
            `safeBinProfiles`.
          '';
        };
        safeBinProfiles = lib.mkOption {
          type = settingsFormat.type;
          default = { };
          example = lib.literalExpression ''
            {
              # allow `git` only with read-only subcommands, no flags that write
              git = { maxPositional = 3; allowedValueFlags = [ ]; deniedFlags = [ "--exec" ]; };
            }
          '';
          description = ''
            Optional per-binary safe-bin profiles (positional-argument limits plus
            allowed/denied flags), mapped straight to tools.exec.safeBinProfiles.
            Use this to admit a binary to `safeBins` only in a constrained form.
            Freeform to track the upstream schema; run `openclaw config schema`.
          '';
        };
        allowlist = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "git status*"
            "git diff*"
            "systemctl status*"
          ];
          description = ''
            Glob patterns pre-seeded into the agent's exec-approval allowlist at
            service start (via `openclaw approvals allowlist add`, for all agents).
            Unlike safeBins (whole-binary), these match the FULL command line, so
            you can bless a read-only SUBCOMMAND — e.g. "git status*" without
            blessing every git invocation. Seeding MERGES (the agent's own
            approve-and-remember additions are preserved) and is idempotent, so it
            is safely re-applied every start. Prefer forms that cannot mutate:
            "git branch*" would also match `git branch -D`, so bless specific
            read-only subcommands, not whole verbs with mutating flags.
          '';
        };
        netIsolatedBins = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "ffmpeg"
            "pandoc"
            "xmllint"
          ];
          description = ''
            Binaries to bless in a NETWORK-ISOLATED form. For each `<bin>` the
            module ships an `offline` launcher (a `unshare --net` wrapper) and seeds
            `offline <bin>*` into the allowlist, so `offline <bin> …` runs WITHOUT
            approval but with no network access — a fail-safe path for network-
            capable converters (ffmpeg/pandoc/xmllint) that would otherwise be data-
            exfiltration channels if blessed bare. The bare `<bin>` is NOT blessed
            by this and keeps prompting. The binary must be reachable independently
            (e.g. via `extraPackages`); this only governs the unprompted `offline`
            form. Tell the agent to prefer `offline <bin>` (the policy skill does).
          '';
        };
      };

      access = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              permissions = lib.mkOption {
                type = lib.types.str;
                default = "rwX";
                example = "rX";
                description = ''
                  ACL permission bits to grant the agent on this path, in setfacl(1)
                  syntax. "rwX" is read/write plus execute/search only where it
                  already applies (directories and already-executable files) — the
                  capital X is what stops it from marking every data file
                  executable. Use "rX" for read-only access.
                '';
              };
              recursive = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Apply the ACL to everything already under this path (setfacl -R),
                  not just the path itself. Set this for a directory whose existing
                  contents the agent should reach.
                '';
              };
              defaultAcl = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Also set a default ACL on this directory (setfacl -d), so entries
                  created under it later inherit the same grant. Without it, only
                  what exists at activation time is covered; new files created by
                  other users would not be readable to the agent.
                '';
              };
            };
          }
        );
        default = { };
        example = lib.literalExpression ''
          {
            "/srv/share" = { permissions = "rwX"; recursive = true; defaultAcl = true; };
            "/etc/some-config.toml" = { permissions = "rX"; };
          }
        '';
        description = ''
          Filesystem paths the agent is granted access to via POSIX ACLs, keyed by
          path. This adds a `user:<agent>:<perms>` ACL entry with setfacl on each
          activation (a oneshot ordered before the service), leaving the path's
          owner and group untouched — it is additive access, not a chown. Use it to
          hand the agent a shared directory or a specific file without making it a
          member of that resource's group.

          The grant is only ever added, never removed: dropping a path here leaves
          the ACL it set in place (clear it by hand with `setfacl -x`). Every path
          here is reachable by anything that reaches the agent, which is
          prompt-injectable — grant the narrowest path and permissions that work.
        '';
      };

      sudoCommands = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = lib.literalExpression ''
          [
            "/run/current-system/sw/bin/systemctl restart some.service"
            "/run/current-system/sw/bin/systemctl start another.service"
          ]
        '';
        description = ''
          Commands the agent may run through sudo (as root) without a password.
          Each entry is a sudoers command spec: an absolute path, optionally
          followed by the exact arguments it is allowed. A path with no arguments
          permits ANY arguments; append `""` to forbid arguments entirely; a bare
          directory (trailing slash) permits anything inside it.

          PREFER exact paths with fixed arguments over open command names or
          wildcards. This account is prompt-injectable (see the header), so every
          entry here is something an attacker who reaches the agent can run as
          root — grant the single narrowest command that does the job.
        '';
      };

      # The bot token and the allowed ID are never Nix VALUES (public repo) — they
      # come in as runtime files via my.openclaw.telegram.{tokenFile,allowedIdFile}
      # above, sourced from whatever secret system the host uses.
    };
  };
in
{
  options.my.openclaw = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openclaw;
      defaultText = lib.literalExpression "pkgs.openclaw";
      description = "OpenClaw package to run.";
    };

    defaultSafeBins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = defaultSafeBins;
      description = ''
        The module's default read-only safeBins set, exposed so host configs
        can write `exec.safeBins = config.my.openclaw.defaultSafeBins ++ [ ... ]`
        when extending a per-instance allowlist.
      '';
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceModule);
      default = { };
      description = ''
        OpenClaw agent instances, keyed by name. Each entry is an independent
        agent with its OWN OS user, home, memory/state dir, Telegram bot and
        loopback gateway service: openclaw-<name>.service, state under
        /var/lib/openclaw/<name>, home at /home/<user>. Agents share only the
        `package` build; their memory, exec policy, sudo grants, ACLs and mail
        identity are fully separate. See the module header for the security
        model, which applies per instance.
      '';
    };
  };

  # The module's `config` MUST expose a STATIC set of top-level attribute names
  # ({ users, systemd, environment, security, system, nixpkgs, services,
  # assertions }) that does NOT depend on evaluating `cfg.instances`. If the
  # top-level shape were derived from the instances (e.g. `mkMerge (mapAttrsToList
  # mkInstance cfg.instances)`), the module system's unmatched-definition check —
  # which needs this module's contributed attr NAMES — would force
  # `cfg.instances`, which builds the submodules, whose own `_module` check forces
  # `config.my.openclaw` again: an infinite recursion (`config → cfg.instances →
  # submodule → config`). Fixing the top-level keys and pulling the per-instance
  # fragments into each key's VALUE only (via `onKey`) keeps the name-level check
  # from forcing the instances; the values are forced later, after options settle.
  # Each fragment is still gated by `lib.mkIf icfg.enable` so a disabled instance
  # contributes nothing.
  config =
    let
      frags = lib.mapAttrsToList (name: icfg: {
        inherit icfg;
        frag = mkInstance name icfg;
      }) cfg.instances;
      onKey = key: lib.mkMerge (map (e: lib.mkIf e.icfg.enable e.frag.${key}) frags);
    in
    {
      users = onKey "users";
      systemd = onKey "systemd";
      environment = onKey "environment";
      security = onKey "security";
      system = onKey "system";
      nixpkgs = onKey "nixpkgs";
      services = onKey "services";

      assertions = lib.mkMerge (
        (map (e: lib.mkIf e.icfg.enable e.frag.assertions) frags)
        ++ [
          [
            {
              assertion =
                let
                  ports = map (i: i.port) (lib.attrValues enabledInstances);
                in
                lib.length ports == lib.length (lib.unique ports);
              message = "my.openclaw.instances: each enabled instance needs a UNIQUE loopback `port` — two gateways cannot bind the same port.";
            }
            {
              assertion =
                let
                  users = map (i: i.user) (lib.attrValues enabledInstances);
                in
                lib.length users == lib.length (lib.unique users);
              message = "my.openclaw.instances: each enabled instance needs a UNIQUE `user` — agents must not share a home/state dir.";
            }
          ]
        ]
      );
    };
}
