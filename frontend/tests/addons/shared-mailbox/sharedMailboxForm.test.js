import { describe, expect, it } from 'vitest'
import fs from 'fs'
import path from 'path'
import {
  answersFromStatus,
  defaultAnswers,
  peopleFromStatus,
  sharedMailboxSetupBody,
  sharedMailboxSetupProblem,
  splitAddresses,
} from '../../../src/addons/shared-mailbox/sharedMailboxForm'

const options = JSON.parse(
  fs.readFileSync(
    path.resolve(
      __dirname,
      '../../../../backend/Config/Addons/shared-mailbox/SharedMailboxOptions.json'
    ),
    'utf8'
  )
)

describe('shared mailbox form helpers', () => {
  it('starts every question on our recommendation', () => {
    expect(defaultAnswers(options)).toEqual({
      grantVia: 'people',
      send: 'sendAs',
      outlook: 'automap',
      sentItems: 'shared',
      signature: 'manual',
      visibility: 'visible',
      external: 'anyone',
      size: 'standard',
    })
  })

  it('takes what an existing mailbox has, keeping the recommendation where it is unknown', () => {
    const answers = answersFromStatus(options, {
      Current: { send: 'sendOnBehalf', outlook: null, visibility: 'hidden' },
    })
    expect(answers.send).toBe('sendOnBehalf')
    expect(answers.outlook).toBe('automap')
    expect(answers.visibility).toBe('hidden')
  })

  it('prefills people from the access group, or from direct Full Access', () => {
    expect(
      peopleFromStatus({
        Group: { Members: [{ Name: 'Jane', Address: 'jane@contoso.com' }] },
        FullAccess: [{ Name: 'G', Address: 'g@contoso.com', IsGroup: true }],
      })
    ).toEqual([{ value: 'jane@contoso.com', label: 'Jane (jane@contoso.com)' }])
    expect(
      peopleFromStatus({
        FullAccess: [
          { Name: 'Tom', Address: 'tom@contoso.com', IsGroup: false },
        ],
      })
    ).toEqual([{ value: 'tom@contoso.com', label: 'Tom (tom@contoso.com)' }])
  })

  it('splits extra addresses typed with commas, spaces or new lines', () => {
    expect(splitAddresses('a@x.com, b@x.com\nc@x.com;')).toEqual([
      'a@x.com',
      'b@x.com',
      'c@x.com',
    ])
  })

  it('builds the request for a new mailbox, sending only the extras the choices need', () => {
    const body = sharedMailboxSetupBody('contoso.com', {
      mode: 'new',
      displayName: ' Info ',
      localPart: 'info',
      domain: { value: 'contoso.com' },
      aliases: 'hello@contoso.com',
      people: [{ value: 'jane@contoso.com' }],
      answers: { ...defaultAnswers(options), signature: 'manual' },
      groupName: 'ignored',
      signatureHtml: 'ignored',
      enableArchive: true,
      blockSignIn: true,
    })
    expect(body.New).toEqual({
      DisplayName: 'Info',
      Address: 'info@contoso.com',
      Aliases: ['hello@contoso.com'],
    })
    expect(body.People).toEqual(['jane@contoso.com'])
    expect(body.GroupName).toBe('')
    expect(body.SignatureHtml).toBe('')
    expect(body.EnableArchive).toBe(false)
    expect(body.Identity).toBeUndefined()
  })

  it('builds the request for an existing mailbox', () => {
    const body = sharedMailboxSetupBody('contoso.com', {
      mode: 'existing',
      mailbox: { value: 'info@contoso.com' },
      answers: { grantVia: 'group', signature: 'rule', size: 'licensed' },
      groupName: ' SG-Info ',
      signatureHtml: '<p>Info</p>',
      enableArchive: true,
      removeOthers: true,
    })
    expect(body.Identity).toBe('info@contoso.com')
    expect(body.GroupName).toBe('SG-Info')
    expect(body.SignatureHtml).toBe('<p>Info</p>')
    expect(body.EnableArchive).toBe(true)
    expect(body.RemoveOthers).toBe(true)
  })

  it('says what is missing before it can run', () => {
    expect(sharedMailboxSetupProblem({ mode: 'new' })).toMatch(/name/)
    expect(
      sharedMailboxSetupProblem({
        mode: 'new',
        displayName: 'Info',
        localPart: 'in fo',
      })
    ).toMatch(/before the @/)
    expect(
      sharedMailboxSetupProblem({
        mode: 'new',
        displayName: 'Info',
        localPart: 'info',
      })
    ).toMatch(/domain/)
    expect(sharedMailboxSetupProblem({ mode: 'existing' })).toMatch(
      /Choose the shared mailbox/
    )
    expect(
      sharedMailboxSetupProblem({
        mode: 'existing',
        mailbox: { value: 'a@b.com' },
        answers: { signature: 'rule' },
      })
    ).toMatch(/signature/)
    expect(
      sharedMailboxSetupProblem({
        mode: 'existing',
        mailbox: { value: 'a@b.com' },
        answers: { signature: 'rule' },
        hasSignatureRule: true,
      })
    ).toBeNull()
  })
})
