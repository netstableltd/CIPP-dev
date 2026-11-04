---
description: Give many users an email address on another domain, as an alias or as their new primary address, from the Users bulk edit.
---

# Bulk email domain

The **Bulk email domain** add-on (`bulk-email-domain`) adds **Email Domain (Alias or Primary Address)** to the bulk edit of users. You need the **Identity.User.ReadWrite** permission.

## Using it

1. Go to **Identity Management > Administration > Users**, tick the users and choose **Edit Properties**. All the users must be in one tenant.
2. In **Properties to update**, choose **Email Domain (Alias or Primary Address)**.
3. Pick the domain. It must be a verified domain in the tenant.
4. Choose what to do with the new address:
   * **Add it as an alias.** Email sent to it arrives, and nothing else changes.
   * **Add it and make it the primary email address.** Emails are sent from it, and the old primary address stays as an alias, so email to it still arrives.
5. Choose where the name before the @ comes from: the **current email address** (the default) or the **sign-in name (UPN)**. A preview shows the first user's new address.
6. Confirm and submit. The results list each user and what happened.

You can choose it alongside other properties in the same run. The other properties are saved as usual; the email change is made separately.

## What is skipped

Each skipped user is listed with the reason:

* users without a mailbox (guests, unlicensed accounts with no mailbox);
* mailboxes synced from on-premises Active Directory, whose addresses have to be changed there;
* a new address another mailbox, group or contact already has;
* two selected users who would get the same address;
* users who already have the address (alias mode), or whose primary address it already is (primary mode).

## Moving a customer to a new domain in stages

Together with **UPN Domain Suffix** (in the same list), a domain change can be done in three steps:

1. **Add the new domain as an alias** for everyone, so email to the new addresses arrives.
2. **Make it the primary address** when the customer is ready to send from it.
3. **Change the UPN domain suffix** when sign-in names should change too. Users then have to sign in again on Outlook, Teams and their phones.

Before step 2, check the new domain's DNS for sending (SPF and DKIM), for example with the Domain Analyser.

## How it works

For each mailbox the add-on builds the new address list the same way as **Add Alias** and **Make Primary** on a user's Exchange tab, and sends all the changes to Exchange Online in one batch (`Set-Mailbox -EmailAddresses`). Sign-in names are not changed.

It adds to CIPP's own Edit Properties page through an extension point: the property comes from the add-on's `userBulkEdit.js`. Turning the add-on off in **Community Additions > Settings > Add-ons** removes the property from the list and blocks its endpoint. Removing the add-on leaves Edit Properties as it was.
