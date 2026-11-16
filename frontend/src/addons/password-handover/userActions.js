// Password hand-over add-on: adds "Reset Password and Send Link" to the user actions menu, through the
// extension point in src/utils/addon-extensions.js. Extension files are loaded with CIPP itself, so this
// one stays light: plain data and one icon.
import { createElement } from 'react'
import KeyIcon from '@mui/icons-material/Key'

export const passwordHandoverAction = {
  label: 'Reset Password and Send Link',
  after: 'Reset Password',
  type: 'POST',
  icon: createElement(KeyIcon),
  url: '/api/ExecPasswordHandover',
  data: {
    ID: 'userPrincipalName',
    displayName: 'displayName',
  },
  defaultvalues: { MustChange: true },
  fields: [
    {
      type: 'switch',
      name: 'MustChange',
      label: 'Must Change Password at Next Logon',
      helperText:
        'Directory-synced (on-premises AD) users always have to choose a new password.',
    },
    {
      type: 'number',
      name: 'ExpireAfterDays',
      label: 'Link lasts (days)',
      placeholder: 'Leave blank for the add-on setting',
    },
    {
      type: 'number',
      name: 'ExpireAfterViews',
      label: 'Link can be opened (times)',
      placeholder: 'Leave blank for the add-on setting',
    },
  ],
  confirmText:
    'Reset the password for [userPrincipalName] and make a Password Pusher link to send them? You get the link and a message ready to send.',
  multiPost: false,
  permissions: ['Identity.User.ReadWrite'],
}

export const userActions = [passwordHandoverAction]
