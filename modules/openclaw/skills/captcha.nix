# solve-captcha skill generator: the WORKFLOW around the wrapper (find the site
# key, plant the returned token). Shipped only when the action is enabled.
{ pkgs, lib, icfg, ... }:

pkgs.writeTextDir "solve-captcha/SKILL.md" ''
        ---
        name: solve-captcha
        description: Solve a CAPTCHA that blocks a page you are working on (reCAPTCHA v2/v3, hCaptcha, Cloudflare Turnstile, FunCaptcha, or a plain image captcha) with the `solve-captcha` command, and plant the returned token so the form submits. Use it when a browser task stalls on a captcha or a form refuses to submit because of one.
        ---

        # Solving a CAPTCHA

        `solve-captcha` sends the captcha to the 2Captcha solving service and prints
        the solution on stdout. It runs WITHOUT approval, but only for pages on the
        allowed host list${
          lib.optionalString (icfg.actions.solveCaptcha.allowedSites != [ ]) ''
             (${lib.concatStringsSep ", " icfg.actions.solveCaptcha.allowedSites})''
        }; any other page is refused outright, so do not try to route
        around it — ask the owner to add the host instead.

        Each solve costs the owner real money and takes ~10–60s. Solve a captcha
        because it stands between you and a task you were ASKED to do — never
        speculatively, and never in a loop: if a solution is rejected twice, stop and
        report it rather than burning credit.

        ## 1. Identify the captcha and read its site key

        With the page open in the browser, the site key is in the DOM:

        - **reCAPTCHA v2**: `div.g-recaptcha[data-sitekey]`, or the `k=` parameter of
          the `/recaptcha/api2/anchor?...` iframe `src`.
        - **reCAPTCHA v3**: the `render=` parameter of the `api.js` script tag.
        - **hCaptcha**: `div.h-captcha[data-sitekey]`.
        - **Turnstile**: `div.cf-turnstile[data-sitekey]`.
        - **Image captcha**: no key — screenshot just the image into your workspace.

        ## 2. Solve

            solve-captcha recaptcha-v2 --url "<page-url>" --sitekey "<key>"
            solve-captcha recaptcha-v2 --url "<page-url>" --sitekey "<key>" --invisible
            solve-captcha recaptcha-v3 --url "<page-url>" --sitekey "<key>" --action submit
            solve-captcha hcaptcha     --url "<page-url>" --sitekey "<key>"
            solve-captcha turnstile    --url "<page-url>" --sitekey "<key>"
            solve-captcha image        captcha.png
            solve-captcha balance                      # remaining account credit

        The `--url` MUST be the page the captcha is actually on (same origin as the
        form) — the solving service binds the token to it, so a wrong URL yields a
        token the page rejects. Write the token to a file rather than piping it into
        another command; a pipe adds a segment that can trip the exec gate.

        ## 3. Plant the token

        A solution is only accepted if it lands where the page's own script looks for
        it. Set the hidden field, then trigger the callback:

        - **reCAPTCHA v2**: fill `textarea#g-recaptcha-response` (make it visible
          first if needed) with the token, then call the widget's `data-callback`
          function if the form has one.
        - **reCAPTCHA v3**: pass the token as the form/request parameter the site
          expects (often `g-recaptcha-response` or a custom field).
        - **hCaptcha**: fill BOTH `textarea[name=h-captcha-response]` and
          `textarea[name=g-recaptcha-response]`.
        - **Turnstile**: fill `input[name=cf-turnstile-response]`.
        - **Image captcha**: type the printed text into the answer input.

        Then submit the form normally and confirm it went through — a page that
        silently re-renders the captcha means the token was not accepted.
      ''
