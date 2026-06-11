# Deploying the website to diffraction.in (Hostinger shared hosting)

The site is uploaded by hand via **hPanel → File Manager**. There is no file-deploy
API on Hostinger shared hosting (only VPS + DNS APIs), so this is a manual upload.

Server account: `u878019455` · web root: `/home/u878019455/domains/diffraction.in/public_html`

---

## 1. Upload these into `public_html/`

| File | Purpose |
|------|---------|
| `index.html`        | Landing page → becomes `diffraction.in`. Static, no backend. |
| `diffract.tar.gz`   | Product release. `install.sh` downloads it from `https://diffraction.in/diffract.tar.gz` — **must sit at public_html root.** (~21 MB; verified current + no bundled secrets.) |
| `install.sh`        | Installer mirror. |
| `signup.html`       | **Payment-first** flow: subscribe → Dodo checkout → (on return) name your workspace. Direct URL only; not linked from the landing page. |
| `.htaccess`         | Denies any `.env`/`.log` from being served; `/api/checkout`, `/api/claim`, `/signup` pretty-URL rewrites. |
| `api/checkout.php`  | Creates the Dodo checkout session (PHP — runs natively on LiteSpeed). Create an `api/` folder and put it inside. |
| `api/claim.php`     | Records the post-payment workspace choice. Goes in the **same `api/` folder**. |

**Do NOT upload** (dev-only): `local-dev-server.py`, `package.json`, `package-lock.json`,
`.gitignore`, `.gitattributes`, `DEPLOY.md`, `.mulch/`, or any `*.example` file.

### Payment-first flow (how it works)

1. `/signup` shows a **Subscribe — ₹2,000/mo** button → POSTs to `api/checkout.php` (no
   workspace/email yet) → redirects to Dodo's hosted checkout. **Dodo collects the email + card.**
2. After paying, Dodo returns the customer to `signup.html?paid=1&<dodo-params>`, which now
   shows a **"name your workspace"** form.
3. That form POSTs to `api/claim.php`, which appends one JSON line — `{workspace, email,
   dodo_ref, ts, ip}` — to **`diffract-signups.log` ONE LEVEL ABOVE `public_html`**
   (auto-created, not web-accessible; `dodo_ref` ties it to the Dodo payment).
4. **You provision each line by hand**, after confirming the matching payment in the Dodo
   dashboard (a line with no matching payment is simply not provisioned).

> File Manager won't show dotfiles by default — toggle **Settings → Show hidden files**
> (dotfiles) so you can see/upload `.htaccess`.

## 2. Place the live payment secret ABOVE public_html (one level up)

Create a file named **`.diffract-dodo.env`** at:

```
/home/u878019455/domains/diffraction.in/.diffract-dodo.env
```

with a single line (template in `.diffract-dodo.env.example`):

```
DODO_PAYMENTS_API_KEY=<the live Dodo key>
```

This is **outside** `public_html`, so it is never web-accessible. `api/checkout.php`
reads it from there. **Never** put the key inside a tracked file or inside `public_html`.

In File Manager: navigate up out of `public_html` to the `diffraction.in` folder,
**New File** → `.diffract-dodo.env` → Edit → paste the line → Save.

## 3. Smoke-test (this does NOT charge anyone)

Creating a checkout *session* is free; a charge only happens if someone actually pays
on Dodo's hosted page. The payment-first flow sends an **empty** body now:

```bash
curl -sS -X POST https://diffraction.in/api/checkout.php \
  -H 'Content-Type: application/json' -d '{}'
```

- ✅ Expect: `{"url":"https://checkout.dodopayments.com/session/...","workspace":""}`
- ❌ `{"error":"payment backend not configured ..."}` → the `.diffract-dodo.env` path or
  permissions are wrong (step 2).
- ❌ `{"error":"request to Dodo failed", ...}` → Hostinger is blocking outbound HTTPS from
  PHP. If so, the checkout backend must move to a VPS instead of shared hosting.

Test the post-payment claim endpoint too (writes one line to `diffract-signups.log` above
public_html — no charge, no payment needed):

```bash
curl -sS -X POST https://diffraction.in/api/claim.php \
  -H 'Content-Type: application/json' \
  -d '{"workspace":"testco","email":"you@example.com","ref":"smoke=1"}'
```

- ✅ Expect: `{"ok":true,"workspace":"testco","url":"https://testco.diffraction.in"}`
- ❌ `{"error":"could not record signup ..."}` → PHP can't write above public_html; check
  folder permissions on `/home/u878019455/domains/diffraction.in/`.

Then open `https://diffraction.in/` (landing) and `https://diffraction.in/signup`
(click **Subscribe** → should redirect to the Dodo checkout page).

---

## ⚠️ Before you take real money

Payments use the **LIVE** Dodo key — real ₹2,000/mo charges. **Auto-provisioning after
payment is NOT built yet.** A customer who pays is *not* automatically given a workspace;
you must provision them manually (Hostinger VPS API → DNS-merge `<ws>.diffraction.in` →
`setup.sh`) until the payment webhook → provisioner exists. Keep `signup.html` unlinked
(soft-hold) until that automation is in place, or fulfil each sale by hand.
