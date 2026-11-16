---
description: Reset a password and send the customer a link to it that expires, with the message ready to send.
---

# Password hand-over

**Reset Password and Send Link** (add-on `password-handover`) sits in the user actions menu, just after **Reset Password**: in Identity Management > Users, on a user's page and in JIT admin. It:

1. resets the user's password (directory-synced users through password writeback);
2. puts the new password behind a Password Pusher link that stops working after a number of days or views, whichever comes first;
3. gives you the link and a message for the customer, each with a copy button.

You need the **Identity.User.ReadWrite** permission to use it, and **CIPP.AppSettings.ReadWrite** to change its settings.

## Before you start: the Password Pusher server

Give the add-on a Password Pusher server, in one of two ways:

* **Password Pusher address** on the Password hand-over page: your own server, used without an API key (anonymous pushes, which most self-hosted servers allow). **Test** makes a throwaway link (1 view, 1 day) to check it works, before or after you save.
* Or leave that blank to use the server in **Settings > Integrations > Password Pusher**, with its API key. You don't need to switch the integration on: if you do, CIPP's own password results (Reset Password, new users, Temporary Access Passes) also give links, with the integration's expiry settings.

The link is made first, and the password is reset only once the link exists. If there is no server, or it doesn't answer, nothing is reset and the action says why. The new password is never shown in plain text.

## In the dialog

* **Must Change Password at Next Logon**: on by default. Directory-synced users always have to choose a new password.
* **Link lasts (days)** and **Link can be opened (times)**: leave blank to use the settings below.

The results show the link (with how long it lasts and the passphrase) and the message for the customer.

## Settings

**Community Additions > Password hand-over** has the settings. They start at:

| Setting | Starts at | What it does |
| --- | --- | --- |
| Password Pusher address | Blank (the integration's server) | See above. |
| Lasts (days) | 14 | 1 to 90. |
| Can be opened (times) | 7 | 1 to 100. |
| Passphrase | The user's email address | Anyone who finds the link also has to know whose password it is. Or none. |
| Ask for a click before showing the password | On | Email link scanners (such as Safe Links) open links; with this on they don't use up the views. |
| Users choose their own password | On | The starting value of the switch in the dialog. |
| Sign-in address, subject and message | A short message in plain English | The message must include `{link}`. |

Placeholders in the subject and message: `{displayName}`, `{userPrincipalName}`, `{link}`, `{views}`, `{expiryDate}`, `{signInUrl}`, `{passphraseLine}` (a sentence about the passphrase, or nothing) and `{mustChangeLine}` (a sentence saying they'll choose their own password, or nothing). The page shows a preview as you type. **Back to the defaults** removes your saved settings.

## What is stored

Only the settings (table `AddonSettings`, row `password-handover` / `settings`). Passwords and links are never stored or written to the logbook; the logbook records that a link was made, for how long and how many views.
