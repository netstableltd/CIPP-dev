import { useEffect } from 'react'
import {
  Alert,
  FormControl,
  FormControlLabel,
  FormLabel,
  Radio,
  RadioGroup,
  Stack,
} from '@mui/material'
import { Controller, useWatch } from 'react-hook-form'
import { CippFormDomainSelector } from '../../components/CippComponents/CippFormDomainSelector'
import { newAddressFor } from './bulkEmailDomain'

/**
 * The value for the bulk email domain property: the domain, whether the new address is an alias or the
 * new primary address, and where the name before the @ comes from. Stored at `${name}.domain`,
 * `${name}.mode` and `${name}.nameFrom`.
 */
export const CippBulkEmailDomainInput = ({ formControl, name, users = [] }) => {
  const value = useWatch({ control: formControl.control, name })

  useEffect(() => {
    if (!value?.mode) formControl.setValue(`${name}.mode`, 'alias')
    if (!value?.nameFrom) formControl.setValue(`${name}.nameFrom`, 'email')
  }, [formControl, name, value?.mode, value?.nameFrom])

  const example = users[0] ? newAddressFor(users[0], value) : ''

  return (
    <Stack spacing={2}>
      <CippFormDomainSelector
        formControl={formControl}
        name={`${name}.domain`}
        label="Email domain"
        preselectDefaultDomain={false}
        showRefresh={true}
      />
      <Controller
        name={`${name}.mode`}
        control={formControl.control}
        render={({ field }) => (
          <FormControl>
            <FormLabel>What to do with the new address</FormLabel>
            <RadioGroup
              value={field.value ?? 'alias'}
              onChange={(e) => field.onChange(e.target.value)}
              aria-label="What to do with the new address"
            >
              <FormControlLabel
                value="alias"
                control={<Radio size="small" />}
                label="Add it as an alias (email to it arrives; nothing else changes)"
              />
              <FormControlLabel
                value="primary"
                control={<Radio size="small" />}
                label="Add it and make it the primary email address (the old one stays as an alias)"
              />
            </RadioGroup>
          </FormControl>
        )}
      />
      <Controller
        name={`${name}.nameFrom`}
        control={formControl.control}
        render={({ field }) => (
          <FormControl>
            <FormLabel>Name before the @</FormLabel>
            <RadioGroup
              row
              value={field.value ?? 'email'}
              onChange={(e) => field.onChange(e.target.value)}
              aria-label="Name before the @"
            >
              <FormControlLabel
                value="email"
                control={<Radio size="small" />}
                label="From the current email address"
              />
              <FormControlLabel
                value="upn"
                control={<Radio size="small" />}
                label="From the sign-in name (UPN)"
              />
            </RadioGroup>
          </FormControl>
        )}
      />
      <Alert severity={value?.mode === 'primary' ? 'warning' : 'info'}>
        {value?.mode === 'primary'
          ? 'Emails will be sent from the new address. Sign-in names don’t change; use UPN Domain Suffix as well if they should.'
          : 'Sign-in names and the primary address don’t change.'}
        {example &&
          ` For example: ${users[0].displayName ?? users[0].userPrincipalName} gets ${example}.`}{' '}
        Users without a mailbox, synced from on-premises, or whose new address
        is already taken are skipped.
      </Alert>
    </Stack>
  )
}

export default CippBulkEmailDomainInput
