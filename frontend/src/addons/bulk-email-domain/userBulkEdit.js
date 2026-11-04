// Bulk email domain add-on: adds "Email Domain" to Identity Management > Users > Edit Properties, through
// the extension point in src/utils/addon-extensions.js. Extension files are loaded with CIPP itself, so
// this one stays light: the input component is loaded only when the property is chosen.
import { lazy } from 'react'
import {
  bulkEmailDomainRequest,
  describeBulkEmailDomain,
  isBulkEmailDomainReady,
} from './bulkEmailDomain'

const CippBulkEmailDomainInput = lazy(() =>
  import('./CippBulkEmailDomainInput').then((m) => ({
    default: m.CippBulkEmailDomainInput,
  }))
)

export const userBulkEditProperties = [
  {
    property: 'addonEmailDomain',
    label: 'Email Domain (Alias or Primary Address)',
    singleTenant: true,
    Input: CippBulkEmailDomainInput,
    describe: describeBulkEmailDomain,
    isReady: isBulkEmailDomainReady,
    request: bulkEmailDomainRequest,
  },
]
