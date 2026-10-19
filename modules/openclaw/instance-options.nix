# Option schema of one agent: my.openclaw.instances.<name>. Implementation in
# ./instance.nix.
{
  config,
  lib,
  pkgs,
  settingsFormat,
  defaultSafeBins,
}:

{ name, ... }:
{
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

    fullName = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "Eva Nebot";
      description = ''
        The agent's human name. Empty means it has none, and mail goes out as a
        bare address.

        Honored when sending: all three send wrappers pass it to sendmail as
        `-F`, so Postfix writes `From: <fullName> <mail.fromAddress>` on the mail
        they submit, and the `check-email` skill shows the agent that same
        identity as the one fixed for it. Postfix applies `-F` only to a message
        with NO `From:` header of its own — which is the case here, since the
        skill tells the agent not to write one and the wrappers pin the sender
        rather than taking it from the message.

        It also becomes the account's GECOS name, so the agent has one name
        across mail and the host rather than two.
      '';
    };

    extraSkillDirs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = lib.literalExpression "[ ./skills ]";
      description = ''
        Extra skill trees to load for this instance, as directories of static
        `<name>/SKILL.md` files (a directory may hold several). They are staged and
        loaded exactly like the ones this module generates.

        This is where WORKING-METHOD skills belong — a way of processing mail, a
        project convention, a house style — as opposed to the skills the module
        renders itself (`policy`, `check-email`, `solve-captcha`, `toolkit`), which
        exist because they must be DERIVED from this instance's configuration and
        would go stale the moment they were written by hand. Content that is just
        prose is better kept as prose: a `.md` file reads and diffs as markdown
        instead of as a Nix string literal, and the module stays agnostic about
        which methods a given agent follows.

        Paths are copied into the store, so the tree is still reproducible and
        pinned by the flake — the agent cannot edit its way out of one of these.
        For a skill the agent should be able to revise itself, put it in its
        workspace instead and leave it out of nix entirely.
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

      prompt = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Heartbeat prompt body (agents.defaults.heartbeat.prompt), sent
          verbatim as the scheduled user message. Null keeps OpenClaw's
          default. A turn that replies NO_REPLY (or calls heartbeat_respond
          with notify = false) delivers nothing, so this is where "stay
          quiet unless something needs the owner" is decided — not
          target = "none", which would also swallow real alerts.
        '';
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
      # into the top-level tts block (see defaultConfig). The provider API key is never a
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
        whisper.cpp CLI entry into tools.media.models and puts whisper-cli +
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
    # embedder or wire a remote key deliberately. Assembles memory.search (and,
    # for "local", the managed llama-cpp provider — see memoryConfig).
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
          Embedding backend (maps to memory.search.provider).
          "local" runs a GGUF model on-box via llama-server — keyless, no
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
          memory.search.local.modelPath and is the `--model` llama-server is
          started with. Ignored by remote
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
          memory.search.model). Null uses the provider default. Not
          used by `provider = "local"` — that takes `localModelPath` instead.
        '';
      };
      llamaCppPackage = lib.mkOption {
        type = lib.types.package;
        default = pkgs.llama-cpp;
        defaultText = lib.literalExpression "pkgs.llama-cpp";
        description = ''
          llama.cpp package providing the `llama-server` openclaw spawns for
          `provider = "local"` embeddings.
        '';
      };
      llamaServerPort = lib.mkOption {
        type = lib.types.port;
        default = 19432; # openclaw's llama-cpp default
        description = ''
          Loopback port of the on-demand llama-server for `provider = "local"`.
          Give each instance its own when several use local embeddings.
        '';
      };
    };

    settings = lib.mkOption {
      inherit (settingsFormat) type;
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

      unpromptedRecipientsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Runtime file adding to `unpromptedRecipients`, one address per line (same
          constraints as actions.trustedMail.trustedAddressesFile). Read by the
          send-email wrapper only when `submitUser` is set — the exec allowlist
          rules cannot come from a runtime file.
        '';
      };

      submitUser = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "eva-mail";
        description = ''
          System account (created here) that the send wrappers run as, through
          sudo. Meant for a host that refuses the agent's own account mail
          submission (authorized_submit_users), which turns the wrappers into
          the only way mail leaves — the recipient checks then hold even when
          nothing gates the agent's commands. send-email no longer delivers to
          a recipient outside the unprompted list: it HOLDS the message in an
          outbox that root lists and releases with `openclaw-outbox-<name>`.
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
        trustedAddressesFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/run/secrets/openclaw/eva/owner-addresses";
          description = ''
            Runtime file adding to `trustedAddresses`, one address per line, so
            they stay out of the store and the repo. It must not be writable by
            the agent (it would widen its own list) and must be readable by
            whoever runs the wrapper: the agent, or `mail.submitUser` when set.
            An unreadable file refuses every send.
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
      checkOura = {
        enable = lib.mkEnableOption ''
          the `check-oura` action: today's Oura Ring readiness score and
          contributors. Destination-fixed to api.ouraring.com, so it is safe to
          bless whole-binary. Needs `tokenFile` set'';
        tokenFile = lib.mkOption {
          type = lib.types.str;
          example = "/run/secrets/openclaw-oura-token";
          description = ''
            Path to a file holding the Oura API Bearer token (single line), read
            at runtime. Point it at a sops-nix secret or any out-of-band file the
            agent can read. The token is never a nix value and does not enter the
            store.
          '';
        };
        apiBase = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "https://api.ouraring.com/v2/usercollection";
          description = ''
            Override the Oura API base URL (default https://api.ouraring.com/v2/usercollection).
          '';
        };
      };
      checkNixosUpdate = {
        enable = lib.mkEnableOption ''
          the `check-nixos-update` action: latest commit on a NixOS channel branch
          from the GitHub API. Destination-fixed to api.github.com/repos/NixOS/nixpkgs,
          so it is safe to bless whole-binary'';
        branch = lib.mkOption {
          type = lib.types.str;
          default = "nixos-24.11";
          example = "nixos-26.05";
          description = ''
            Default NixOS channel branch to check (e.g. "nixos-26.05").
            The agent can override this per-call with --branch.
          '';
        };
        apiBase = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "https://api.github.com";
          description = ''
            Override the GitHub API base URL (default https://api.github.com).
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
            (`settings.browser.ssrfPolicy.allowedHostnames`), so a prompt-injected
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
      makeInvite = {
        enable = lib.mkEnableOption ''
          the `make-invite` action: compose a calendar INVITATION (iTIP) that the
          recipient's mail client offers to accept or decline, instead of a .ics
          file it can only save. It writes the message to stdout and sends
          nothing — the agent redirects it into `send-trusted-mail` or
          `send-email`, so an invitation is gated by the recipient rules already
          in force and there is no second self-limiting sender to keep in step.
          Needs `mail.fromAddress` (it becomes the ORGANIZER, which clients
          require to match the From: the mail goes out with); `fullName`, when
          set, becomes the organizer's display name. Blessed whole-binary:
          composing text has no destination and reaches no network'';
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
      zotero = {
        enable = lib.mkEnableOption ''
          the Zotero actions — the agent's whole reference-manager surface, as TWO
          command names over one script so the role is legible in the command:
          `check-zotero` (GET only — search / doi / collections / item) and
          `zotero-add` (CREATE items from a JSON array on stdin or in a file, so a
          reference verified against Crossref/PubMed reaches the library instead of
          being handed over as a .ris to import by hand). Needs `tokenFile`.

          The READ half is a security feature, not a convenience: the alternative is
          the agent calling `request-trusted-url ".../items?key=<key>&q=…"`, which
          only works if the agent KNOWS the key — putting it in a command line the
          agent composed, and therefore in its transcript, its exec log and its
          memory index. Here the wrapper reads the key from a file and injects it as
          a header, so it never enters anything the agent writes. Enabling this means
          api.zotero.org does NOT belong in `actions.requestUrl.trustedSites`.

          Both names are blessed whole-binary, one of them despite being a write,
          because what matters is pinned rather than passed: the ENDPOINT is fixed
          (the agent supplies query text or item data, never a URL, so neither can
          become a generic fetch or POST the way a blessed raw `curl` would), the
          LIBRARY is the one the API key owns, and the write is CREATE-ONLY — items
          carrying `key` or `version` (what a Zotero update looks like) are refused
          and DELETE is never issued, so no existing reference can be overwritten or
          destroyed. The residual channel is item text going into the owner's own
          library, which is a place to write nonsense rather than a place to
          exfiltrate to.

          `zotero-add` does NOT deduplicate — `check-zotero doi <doi>` first'';
        tokenFile = lib.mkOption {
          type = lib.types.str;
          example = "/run/secrets/openclaw-zotero-token";
          description = ''
            Path to a file holding the Zotero API key (single line), read at RUNTIME —
            a `str` path (not a `path`), so the key never enters the store or this
            repo. The key must have write access to the target library. It is passed
            to curl through a 0600 config file, so it is not visible in the process
            table.
          '';
        };
        library = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "users/1234567";
          description = ''
            The library both commands act on, as `users/<id>` or `groups/<id>`. NULL (the
            default) resolves it at runtime from the API key itself
            (`GET /keys/current`), which means the operator only ever has to supply
            the key, and the reachable library is by construction the one that key
            owns. Set it explicitly to pin a group library, or when the key's own
            user is not the target.
          '';
        };
        maxItems = lib.mkOption {
          type = lib.types.ints.positive;
          default = 50;
          description = ''
            Maximum items `zotero-add` accepts per invocation. The Zotero API itself
            caps a write at 50; lowering this makes the agent send smaller, more
            reviewable batches.
          '';
        };
        apiBase = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "https://api.zotero.org";
          description = ''
            Override the API base URL (default https://api.zotero.org). The wrapper
            uses raw curl, so whatever host this resolves to must be reachable; it is
            not bound by `actions.requestUrl.trustedSites`.
          '';
        };
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
        inherit (settingsFormat) type;
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

    egress = {
      enable = lib.mkEnableOption ''
        network egress filtering: the agent's uid may only open connections to
        the module's filtering proxy (my.openclaw.egressProxy), its own gateway
        ports and the local resolver; the proxy only forwards to an allowlist
        derived from this instance (channel, model provider, TTS, the wrappers'
        hosts, request-trusted-url and captcha sites) plus `allowedDomains`'';
      allowedDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "github.com"
          "*.githubusercontent.com"
        ];
        description = ''
          Extra hosts the agent may reach, as fnmatch patterns (`*.example.com`
          does not cover the apex). Proxy denials show in
          `journalctl -u tinyproxy` as "Proxying refused on filtered domain".
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
}
