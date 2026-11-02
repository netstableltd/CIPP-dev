---
description: Set up a shared mailbox the way the customer chooses, with a PDF of the choices before and a guide for their team after.
---

# Shared mailbox

**Community Additions > Shared mailbox** (add-on `shared-mailbox`) sets up a shared mailbox in the selected tenant. Each choice about how it should work is put to the customer first, with what it means for their team. Then one button creates the mailbox, or updates an existing one, with all of them. You need the **Exchange.Mailbox** permission.

## 1. Ask the customer

**The choices, for the customer** makes a branded PDF to send them. It has:

* the request, what we always do (block sign-in to the mailbox itself; UK language and time zone), and the other options if a shared mailbox isn't the right fit (a Microsoft 365 group, a distribution list, a ticketing system);
* the eight choices, each with its options, what they mean, their pros and cons, and our recommendation;
* a reply list for the customer to copy into an email.

| Choice | Options (recommended first) | What it changes |
| --- | --- | --- |
| Giving people access | Person by person; through a group | A group makes joiners and leavers a group change, but the mailbox then doesn't appear in Outlook by itself. |
| Sending | Send as; send on behalf; read only | Send as shows only the shared address. Send on behalf shows "Jane on behalf of Info". Only one is granted, because granting both confuses Outlook. |
| In Outlook | Automatically (automapping); as a separate account | Automapped: nothing to set up, but new emails start from the person's own address and there is no automatic signature. Separate account: the From address and signature are always right, but each computer needs setting up. |
| Sent emails | In the shared mailbox too; only the sender's | Sets `MessageCopyForSentAsEnabled` and `MessageCopyForSendOnBehalfEnabled`. |
| Signature | People choose it; added automatically by Microsoft 365; a signature service | "Added automatically" is a mail flow rule (`Shared mailbox signature - <address>`) that appends the signature to everything sent from the address. |
| Address book | Show; hide | `HiddenFromAddressListsEnabled`. |
| Who can email it | Anyone; only the business | `RequireSenderAuthenticationEnabled`. |
| Size and licence | Standard (50 GB, no licence); licensed (100 GB, archive, legal hold) | Licensed needs an Exchange Online Plan 1 licence, which you assign. The archive can then be turned on here. |

The questions, options and wording live in `backend/Config/Addons/shared-mailbox/SharedMailboxOptions.json`. The PDF, the page and the setup all read from that file.

## 2. The mailbox

Choose **New mailbox** (name, address, domain and any other addresses it receives email for) or **Existing mailbox**. An existing mailbox shows how it is set up now, and its current settings and people are filled in as the starting point. Whether automapping is on can't be read from Exchange.

## 3. The customer's choices

Pick the people who need access and record the customer's answers. Our recommendations are selected to start with, and the chosen option's pros and cons are shown under each question. Some choices need more details: the access group's name, the signature (HTML), or turning on the archive.

Under **More settings**:

* **Block sign-in** to the mailbox account (on by default).
* **Take access away from anyone not listed**. Otherwise people who already have access are left alone.
* **Re-grant Full Access** to the listed people, so automapping matches the Outlook choice. Exchange can't change automapping on an existing permission.
* **Language and time zone** (en-GB, GMT Standard Time).

**Create the shared mailbox** (or **Apply**) lists every step and whether it worked. It is safe to run again; only what differs is changed.

## 4. Tell the customer it's ready

The "ready" PDF reads the mailbox from the tenant and has:

* how it is set up;
* anything not finished, for example nobody with access yet or a licence still needed;
* a guide for the team matched to their choices: adding the mailbox (classic Outlook, new Outlook and the web, phones), sending from it (including picking the From address), the signature, and working together in it.

**Step-by-step guide**: upload your own Word guide with screenshots, for example sending as the shared address in Outlook. It is kept in this CIPP instance (not in the code) and added to the end of every customer's "ready" PDF. Use the switch to leave it out.
