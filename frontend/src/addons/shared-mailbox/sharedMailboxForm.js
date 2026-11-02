/**
 * Pure helpers for the shared mailbox add-on's page: defaults from the question set, prefilling from an
 * existing mailbox, and the request bodies.
 */

/** Our recommendation for every question: { questionId: optionId }. */
export const defaultAnswers = (options) =>
  Object.fromEntries(
    (options?.questions ?? []).map((q) => [
      q.id,
      (q.options.find((o) => o.recommended) ?? q.options[0])?.id,
    ])
  )

/** The answers an existing mailbox amounts to, falling back to the recommendation where unknown. */
export const answersFromStatus = (options, status) => {
  const answers = defaultAnswers(options)
  Object.entries(status?.Current ?? {}).forEach(([key, value]) => {
    if (value && key in answers) answers[key] = value
  })
  return answers
}

/** People with access to an existing mailbox, as user-picker values (sign-in name / address). */
export const peopleFromStatus = (status) => {
  const people = status?.Group
    ? (status.Group.Members ?? [])
    : (status?.FullAccess ?? []).filter((p) => !p.IsGroup)
  return people
    .filter((p) => p.Address)
    .map((p) => ({
      value: p.Address,
      label: p.Name ? `${p.Name} (${p.Address})` : p.Address,
    }))
}

/** Extra addresses typed one per line or separated by commas. */
export const splitAddresses = (text) =>
  String(text ?? '')
    .split(/[\s,;]+/)
    .map((a) => a.trim())
    .filter(Boolean)

const domainOf = (value) => value?.value ?? value ?? ''

/** The request body for ExecSharedMailboxSetup, from the form. */
export const sharedMailboxSetupBody = (tenant, values) => {
  const body = {
    tenantFilter: tenant,
    People: (values.people ?? []).map((p) => p?.value ?? p).filter(Boolean),
    Answers: values.answers,
    GroupName:
      values.answers?.grantVia === 'group'
        ? (values.groupName ?? '').trim()
        : '',
    SignatureHtml:
      values.answers?.signature === 'rule' ? (values.signatureHtml ?? '') : '',
    EnableArchive:
      values.answers?.size === 'licensed' && Boolean(values.enableArchive),
    BlockSignIn: values.blockSignIn !== false,
    RemoveOthers: Boolean(values.removeOthers),
    ReapplyAccess: Boolean(values.reapplyAccess),
    Language: (values.language ?? '').trim(),
    TimeZone: (values.timeZone ?? '').trim(),
  }
  if (values.mode === 'new') {
    const local = (values.localPart ?? '').trim()
    body.New = {
      DisplayName: (values.displayName ?? '').trim(),
      Address:
        local && domainOf(values.domain)
          ? `${local}@${domainOf(values.domain)}`
          : local,
      Aliases: splitAddresses(values.aliases),
    }
  } else {
    body.Identity = values.mailbox?.value ?? values.mailbox ?? ''
  }
  return body
}

/** What's missing before the setup can run, or null. */
export const sharedMailboxSetupProblem = (values) => {
  if (values.mode === 'new') {
    if (!(values.displayName ?? '').trim()) return 'Give the mailbox a name.'
    if (!/^[A-Za-z0-9._%+'-]+$/.test((values.localPart ?? '').trim()))
      return 'Give the part of the address before the @.'
    if (!domainOf(values.domain)) return 'Choose the domain.'
  } else if (!(values.mailbox?.value ?? values.mailbox)) {
    return 'Choose the shared mailbox.'
  }
  if (
    values.answers?.signature === 'rule' &&
    !(values.signatureHtml ?? '').trim() &&
    !values.hasSignatureRule
  ) {
    return 'Add the signature the rule should put on emails.'
  }
  return null
}
