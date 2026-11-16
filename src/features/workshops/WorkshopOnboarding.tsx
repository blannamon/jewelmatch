import { useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'

type City = { id: string; name: string; region_id: string }
type ServiceCategory = { id: string; name: string }
type Organization = {
  id: string
  name: string
  city_id: string
  phone_public: string
  email_public: string | null
  telegram_public: string | null
  website_public: string | null
  description: string | null
  accepts_remote: boolean
}
type Coverage = {
  id: string
  scope_type: 'city' | 'region'
  city_id: string | null
  region_id: string | null
}

type Props = {
  session: Session
  showOptionalFields?: boolean
  onComplete: () => void
}

const blankProfile = {
  name: '',
  cityId: '',
  phone: '',
  email: '',
  telegram: '',
  website: '',
  description: '',
}

export default function WorkshopOnboarding({
  session,
  showOptionalFields = false,
  onComplete,
}: Props) {
  const [cities, setCities] = useState<City[]>([])
  const [categories, setCategories] = useState<ServiceCategory[]>([])
  const [organizationId, setOrganizationId] = useState<string | null>(null)
  const [profile, setProfile] = useState(blankProfile)
  const [selectedServices, setSelectedServices] = useState<string[]>([])
  const [coversCity, setCoversCity] = useState(false)
  const [coversRegion, setCoversRegion] = useState(false)
  const [acceptsRemote, setAcceptsRemote] = useState(false)
  const [step, setStep] = useState<1 | 2>(1)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    if (!supabase) return
    const client = supabase
    let active = true

    const loadForm = async () => {
      const [cityResult, categoryResult, organizationResult] =
        await Promise.all([
          client.from('cities').select('id,name,region_id').order('name'),
          client
            .from('service_categories')
            .select('id,name')
            .eq('is_active', true)
            .order('sort_order'),
          client
            .from('organizations')
            .select(
              'id,name,city_id,phone_public,email_public,telegram_public,website_public,description,accepts_remote',
            )
            .eq('owner_user_id', session.user.id)
            .order('created_at', { ascending: true })
            .limit(1)
            .maybeSingle(),
        ])

      if (!active) return
      if (
        cityResult.error ||
        categoryResult.error ||
        organizationResult.error
      ) {
        setError(
          'Не удалось загрузить справочники. Обновите страницу и попробуйте ещё раз.',
        )
        setLoading(false)
        return
      }

      const loadedCities = (cityResult.data ?? []) as City[]
      const loadedCategories = (categoryResult.data ?? []) as ServiceCategory[]
      setCities(loadedCities)
      setCategories(loadedCategories)

      const organization = organizationResult.data as Organization | null
      if (organization) {
        setOrganizationId(organization.id)
        setProfile({
          name: organization.name,
          cityId: organization.city_id,
          phone: organization.phone_public,
          email: organization.email_public ?? '',
          telegram: organization.telegram_public ?? '',
          website: organization.website_public ?? '',
          description: organization.description ?? '',
        })
        setAcceptsRemote(organization.accepts_remote)

        const [serviceResult, coverageResult] = await Promise.all([
          client
            .from('organization_services')
            .select('service_category_id')
            .eq('organization_id', organization.id),
          client
            .from('organization_service_areas')
            .select('id,scope_type,city_id,region_id')
            .eq('organization_id', organization.id),
        ])
        if (!active) return
        if (serviceResult.error || coverageResult.error) {
          setError('Не удалось загрузить услуги мастерской. Обновите страницу.')
        } else {
          setSelectedServices(
            (serviceResult.data ?? []).map((item) => item.service_category_id),
          )
          const areas = (coverageResult.data ?? []) as Coverage[]
          setCoversCity(areas.some((area) => area.scope_type === 'city'))
          setCoversRegion(areas.some((area) => area.scope_type === 'region'))
        }
      } else {
        const displayName = session.user.user_metadata.display_name
        setProfile((current) => ({
          ...current,
          name: typeof displayName === 'string' ? displayName : '',
        }))
      }
      setLoading(false)
    }

    void loadForm()
    return () => {
      active = false
    }
  }, [session.user.id, session.user.user_metadata.display_name])

  const toggleService = (id: string) => {
    setSelectedServices((current) =>
      current.includes(id)
        ? current.filter((selectedId) => selectedId !== id)
        : [...current, id],
    )
  }

  const saveProfile = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (step === 1) {
      setStep(2)
      return
    }
    if (!supabase) return
    setError('')

    if (selectedServices.length === 0) {
      setError('Выберите хотя бы одну специализацию.')
      return
    }
    if (!coversCity && !coversRegion && !acceptsRemote) {
      setError('Выберите, где мастерская принимает заказы.')
      return
    }

    const city = cities.find((item) => item.id === profile.cityId)
    if (!city) {
      setError('Выберите город мастерской.')
      return
    }

    const websiteInput = profile.website.trim()
    let publicWebsite: string | null = null
    if (websiteInput) {
      try {
        const value = /^https?:\/\//i.test(websiteInput)
          ? websiteInput
          : `https://${websiteInput}`
        const parsedWebsite = new URL(value)
        if (!parsedWebsite.hostname.includes('.'))
          throw new Error('Invalid hostname')
        publicWebsite = parsedWebsite.toString()
      } catch {
        setError('Введите адрес сайта или соцсети, например example.com.')
        return
      }
    }

    setBusy(true)
    const values = {
      name: profile.name.trim(),
      city_id: profile.cityId,
      phone_public: profile.phone.trim(),
      email_public: profile.email.trim() || null,
      telegram_public: profile.telegram.trim() || null,
      website_public: publicWebsite,
      description: profile.description.trim() || null,
      accepts_remote: acceptsRemote,
    }

    let savedId = organizationId
    if (organizationId) {
      const { error: updateError } = await supabase
        .from('organizations')
        .update(values)
        .eq('id', organizationId)
      if (updateError) {
        setError(
          'Не удалось сохранить основные данные. Проверьте поля и попробуйте ещё раз.',
        )
        setBusy(false)
        return
      }
    } else {
      const { data, error: insertError } = await supabase
        .from('organizations')
        .insert({ ...values, owner_user_id: session.user.id })
        .select('id')
        .single()
      if (insertError || !data) {
        setError('Не удалось создать профиль мастерской. Попробуйте ещё раз.')
        setBusy(false)
        return
      }
      savedId = data.id
      setOrganizationId(data.id)
    }

    if (!savedId) {
      setError('Не удалось определить профиль мастерской. Обновите страницу.')
      setBusy(false)
      return
    }

    const { data: currentServices, error: currentServicesError } =
      await supabase
        .from('organization_services')
        .select('service_category_id')
        .eq('organization_id', savedId)
    if (currentServicesError) {
      setError(
        'Основные данные сохранены, но список услуг не загрузился. Нажмите «Сохранить профиль» ещё раз.',
      )
      setBusy(false)
      return
    }

    const currentServiceIds = (currentServices ?? []).map(
      (item) => item.service_category_id,
    )
    const servicesToAdd = selectedServices.filter(
      (id) => !currentServiceIds.includes(id),
    )
    const servicesToRemove = currentServiceIds.filter(
      (id) => !selectedServices.includes(id),
    )

    if (servicesToAdd.length > 0) {
      const { error: addServicesError } = await supabase
        .from('organization_services')
        .insert(
          servicesToAdd.map((service_category_id) => ({
            organization_id: savedId,
            service_category_id,
          })),
        )
      if (addServicesError) {
        setError(
          'Основные данные сохранены, но специализации не записались. Проверьте их и нажмите «Сохранить профиль» ещё раз.',
        )
        setBusy(false)
        return
      }
    }

    if (servicesToRemove.length > 0) {
      const { error: removeServicesError } = await supabase
        .from('organization_services')
        .delete()
        .eq('organization_id', savedId)
        .in('service_category_id', servicesToRemove)
      if (removeServicesError) {
        setError(
          'Не удалось обновить список специализаций. Нажмите «Сохранить профиль» ещё раз.',
        )
        setBusy(false)
        return
      }
    }

    const desiredAreas = [
      ...(coversCity
        ? [{ scope_type: 'city' as const, city_id: city.id, region_id: null }]
        : []),
      ...(coversRegion
        ? [
            {
              scope_type: 'region' as const,
              city_id: null,
              region_id: city.region_id,
            },
          ]
        : []),
    ]
    const { data: currentAreas, error: currentAreasError } = await supabase
      .from('organization_service_areas')
      .select('id,scope_type,city_id,region_id')
      .eq('organization_id', savedId)
    if (currentAreasError) {
      setError(
        'Основные данные сохранены, но территорию обслуживания не удалось загрузить. Нажмите «Сохранить профиль» ещё раз.',
      )
      setBusy(false)
      return
    }

    const areas = (currentAreas ?? []) as Coverage[]
    const areaMatches = (area: Omit<Coverage, 'id'>) =>
      areas.some(
        (current) =>
          current.scope_type === area.scope_type &&
          current.city_id === area.city_id &&
          current.region_id === area.region_id,
      )
    const areasToAdd = desiredAreas.filter((area) => !areaMatches(area))
    const areasToRemove = areas.filter(
      (current) =>
        !desiredAreas.some(
          (desired) =>
            current.scope_type === desired.scope_type &&
            current.city_id === desired.city_id &&
            current.region_id === desired.region_id,
        ),
    )

    if (areasToAdd.length > 0) {
      const { error: addAreasError } = await supabase
        .from('organization_service_areas')
        .insert(
          areasToAdd.map((area) => ({
            ...area,
            organization_id: savedId,
          })),
        )
      if (addAreasError) {
        setError(
          'Основные данные сохранены, но территорию обслуживания записать не удалось. Нажмите «Сохранить профиль» ещё раз.',
        )
        setBusy(false)
        return
      }
    }

    if (areasToRemove.length > 0) {
      const { error: removeAreasError } = await supabase
        .from('organization_service_areas')
        .delete()
        .eq('organization_id', savedId)
        .in(
          'id',
          areasToRemove.map((area) => area.id),
        )
      if (removeAreasError) {
        setError(
          'Не удалось обновить территорию обслуживания. Нажмите «Сохранить профиль» ещё раз.',
        )
        setBusy(false)
        return
      }
    }

    setBusy(false)
    onComplete()
  }

  if (loading) {
    return (
      <div className="form-content" aria-live="polite">
        <p className="eyebrow">Профиль мастерской</p>
        <h2 id="auth-title">Загружаем справочники</h2>
        <div className="loading-line" />
      </div>
    )
  }

  return (
    <div className="form-content workshop-form-content">
      <p className="eyebrow">Шаг {step} из 2 · Мастерская</p>
      <h2 id="auth-title">
        {step === 1 ? 'Основное о мастерской' : 'Какие заказы вам подходят?'}
      </h2>
      <p className="muted">
        {step === 1
          ? 'Только самое нужное. Профиль можно дополнить позже.'
          : 'Выберите специализацию и территорию работы.'}
      </p>
      <div
        className="onboarding-progress"
        role="progressbar"
        aria-label={`Шаг ${step} из 2`}
        aria-valuemin={1}
        aria-valuemax={2}
        aria-valuenow={step}
      >
        <span className={step === 1 ? 'active' : 'complete'} />
        <span className={step === 2 ? 'active' : ''} />
      </div>

      <form className="auth-form workshop-form" onSubmit={saveProfile}>
        {step === 1 ? (
          <>
            <div className="form-field">
              <label htmlFor="workshop-name">Название мастерской или имя</label>
              <input
                id="workshop-name"
                autoComplete="organization"
                maxLength={160}
                value={profile.name}
                onChange={(event) =>
                  setProfile({ ...profile, name: event.target.value })
                }
                required
              />
            </div>

            <div className="form-field">
              <label htmlFor="workshop-city">Город</label>
              <select
                id="workshop-city"
                value={profile.cityId}
                onChange={(event) =>
                  setProfile({ ...profile, cityId: event.target.value })
                }
                required
              >
                <option value="" disabled>
                  Выберите город
                </option>
                {cities.map((city) => (
                  <option key={city.id} value={city.id}>
                    {city.name}
                  </option>
                ))}
              </select>
            </div>

            <div className="form-field">
              <label htmlFor="workshop-phone">Телефон для связи</label>
              <input
                id="workshop-phone"
                type="tel"
                autoComplete="tel"
                maxLength={80}
                placeholder="+373 …"
                value={profile.phone}
                onChange={(event) =>
                  setProfile({ ...profile, phone: event.target.value })
                }
                required
              />
            </div>
          </>
        ) : (
          <>
            <fieldset className="choice-fieldset">
              <legend>Специализация</legend>
              <div className="check-grid">
                {categories.map((category) => (
                  <label className="check-option" key={category.id}>
                    <input
                      type="checkbox"
                      checked={selectedServices.includes(category.id)}
                      onChange={() => toggleService(category.id)}
                    />
                    <span>{category.name}</span>
                  </label>
                ))}
              </div>
            </fieldset>

            <fieldset className="choice-fieldset">
              <legend>Где принимаете заказы?</legend>
              <div className="check-grid coverage-grid">
                <label className="check-option">
                  <input
                    type="checkbox"
                    checked={coversCity}
                    onChange={(event) => setCoversCity(event.target.checked)}
                  />
                  <span>В своём городе</span>
                </label>
                <label className="check-option">
                  <input
                    type="checkbox"
                    checked={coversRegion}
                    onChange={(event) => setCoversRegion(event.target.checked)}
                  />
                  <span>По всему Приднестровью</span>
                </label>
                <label className="check-option">
                  <input
                    type="checkbox"
                    checked={acceptsRemote}
                    onChange={(event) => setAcceptsRemote(event.target.checked)}
                  />
                  <span>Дистанционно</span>
                </label>
              </div>
            </fieldset>
          </>
        )}

        {showOptionalFields && step === 2 && (
          <details className="optional-profile-fields">
            <summary>Дополнительная информация</summary>
            <div className="optional-fields-content">
              <div className="form-field">
                <label htmlFor="workshop-email">Публичная почта</label>
                <input
                  id="workshop-email"
                  type="email"
                  autoComplete="email"
                  maxLength={254}
                  placeholder="workshop@example.com"
                  value={profile.email}
                  onChange={(event) =>
                    setProfile({ ...profile, email: event.target.value })
                  }
                />
              </div>
              <div className="form-field">
                <label htmlFor="workshop-telegram">Telegram</label>
                <input
                  id="workshop-telegram"
                  maxLength={160}
                  placeholder="@username"
                  value={profile.telegram}
                  onChange={(event) =>
                    setProfile({ ...profile, telegram: event.target.value })
                  }
                />
              </div>
              <div className="form-field">
                <label htmlFor="workshop-website">Сайт или соцсеть</label>
                <input
                  id="workshop-website"
                  type="text"
                  inputMode="url"
                  autoComplete="url"
                  maxLength={500}
                  placeholder="example.com"
                  value={profile.website}
                  onChange={(event) =>
                    setProfile({ ...profile, website: event.target.value })
                  }
                />
                <p className="field-hint">
                  Можно указать домен без https:// — добавим его автоматически.
                </p>
              </div>
              <div className="form-field">
                <label htmlFor="workshop-description">О мастерской</label>
                <textarea
                  id="workshop-description"
                  rows={4}
                  maxLength={10000}
                  placeholder="Расскажите о своём опыте и работах"
                  value={profile.description}
                  onChange={(event) =>
                    setProfile({ ...profile, description: event.target.value })
                  }
                />
              </div>
            </div>
          </details>
        )}

        <div className="onboarding-actions">
          {step === 2 && (
            <button
              className="back-button"
              type="button"
              disabled={busy}
              onClick={() => setStep(1)}
            >
              ← Назад
            </button>
          )}
          <button
            className="primary-button"
            type="submit"
            disabled={
              busy ||
              cities.length === 0 ||
              (step === 2 && categories.length === 0)
            }
          >
            {busy ? 'Сохраняем…' : step === 1 ? 'Далее' : 'Готово'}
            <span aria-hidden="true">↗</span>
          </button>
        </div>
      </form>
      {error && (
        <p className="error-message" role="alert">
          {error}
        </p>
      )}
    </div>
  )
}
