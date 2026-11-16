import { useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import type { AuthChangeEvent, Session } from '@supabase/supabase-js'
import WorkshopOnboarding from './features/workshops/WorkshopOnboarding'
import { isSupabaseConfigured, supabase } from './lib/supabase'

type AppRole = 'customer' | 'workshop' | 'admin'
type Screen =
  'auth' | 'confirm' | 'recovery' | 'role' | 'workshop-onboarding' | 'home'
type AuthMode = 'signin' | 'signup'

const roleCopy: Record<
  Exclude<AppRole, 'admin'>,
  { title: string; detail: string }
> = {
  customer: {
    title: 'Заказчик',
    detail: 'Создавайте заказы и находите ювелиров для своих идей.',
  },
  workshop: {
    title: 'Мастерская',
    detail: 'Получайте подходящие заказы и расскажите клиентам о своей работе.',
  },
}

const telegramEnabled =
  import.meta.env.VITE_SUPABASE_TELEGRAM_ENABLED === 'true'

export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [role, setRole] = useState<AppRole | null>(null)
  const [screen, setScreen] = useState<Screen>('auth')
  const [editingWorkshopProfile, setEditingWorkshopProfile] = useState(false)
  const [authMode, setAuthMode] = useState<AuthMode>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [passwordConfirm, setPasswordConfirm] = useState('')
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(isSupabaseConfigured)
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    if (!supabase) return
    const client = supabase

    let active = true
    const loadProfile = async (nextSession: Session) => {
      if (!active) return
      setLoading(true)
      const { data, error: profileError } = await client
        .from('profiles')
        .select('role')
        .eq('user_id', nextSession.user.id)
        .maybeSingle()
      if (!active) return
      if (profileError)
        setError('Не удалось загрузить профиль. Обновите страницу.')
      const nextRole = (data?.role as AppRole | null) ?? null
      setRole(nextRole)
      if (nextRole === 'workshop') {
        const { data: organization, error: organizationError } = await client
          .from('organizations')
          .select('id,accepts_remote')
          .eq('owner_user_id', nextSession.user.id)
          .order('created_at', { ascending: true })
          .limit(1)
          .maybeSingle()
        if (!active) return
        if (organizationError) {
          setError(
            'Не удалось проверить профиль мастерской. Обновите страницу.',
          )
          setScreen('workshop-onboarding')
        } else if (!organization) {
          setScreen('workshop-onboarding')
        } else {
          const [serviceResult, areaResult] = await Promise.all([
            client
              .from('organization_services')
              .select('service_category_id')
              .eq('organization_id', organization.id),
            client
              .from('organization_service_areas')
              .select('id')
              .eq('organization_id', organization.id),
          ])
          if (!active) return
          const complete =
            (serviceResult.data?.length ?? 0) > 0 &&
            ((areaResult.data?.length ?? 0) > 0 || organization.accepts_remote)
          setScreen(complete ? 'home' : 'workshop-onboarding')
          if (serviceResult.error || areaResult.error)
            setError('Не удалось проверить завершённость профиля мастерской.')
        }
      } else {
        setScreen(nextRole ? 'home' : 'role')
      }
      setLoading(false)
    }
    const updateSession = (
      nextSession: Session | null,
      event: AuthChangeEvent,
    ) => {
      if (!active) return
      setSession(nextSession)
      setRole(null)
      if (event === 'PASSWORD_RECOVERY') {
        setScreen('recovery')
        setLoading(false)
        return
      }
      if (!nextSession) {
        if (event === 'SIGNED_OUT') setScreen('auth')
        setLoading(false)
        return
      }
      // Defer profile queries until the auth state callback releases its internal lock.
      window.setTimeout(() => void loadProfile(nextSession), 0)
    }

    void client.auth
      .getSession()
      .then(({ data }) => updateSession(data.session, 'INITIAL_SESSION'))
    const { data: authListener } = client.auth.onAuthStateChange(
      (event, nextSession) => updateSession(nextSession, event),
    )

    return () => {
      active = false
      authListener.subscription.unsubscribe()
    }
  }, [])

  const handleAuth = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!supabase) return
    setBusy(true)
    setError('')
    setNotice('')

    if (authMode === 'signup') {
      const { data, error: authError } = await supabase.auth.signUp({
        email: email.trim(),
        password,
        options: { emailRedirectTo: window.location.origin },
      })
      if (authError)
        setError(
          'Не удалось создать аккаунт. Проверьте данные и попробуйте снова.',
        )
      else if (!data.session) {
        setScreen('confirm')
        setNotice('Отправили письмо со ссылкой для подтверждения адреса.')
      }
    } else {
      const { error: authError } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      })
      if (authError) setError('Не удалось войти. Проверьте почту и пароль.')
    }
    setBusy(false)
  }

  const resendConfirmation = async () => {
    if (!supabase) return
    setBusy(true)
    setError('')
    const { error: authError } = await supabase.auth.resend({
      type: 'signup',
      email: email.trim(),
      options: { emailRedirectTo: window.location.origin },
    })
    if (authError) setError('Не удалось отправить письмо. Попробуйте позже.')
    else setNotice('Письмо отправлено повторно. Проверьте также папку «Спам».')
    setBusy(false)
  }

  const sendPasswordReset = async () => {
    if (!supabase) return
    if (!email.trim()) {
      setError('Сначала укажите электронную почту.')
      return
    }
    setBusy(true)
    setError('')
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(
      email.trim(),
      { redirectTo: window.location.origin },
    )
    if (resetError) setError('Не удалось отправить письмо. Попробуйте позже.')
    else
      setNotice(
        'Если аккаунт с такой почтой существует, мы отправили ссылку для сброса пароля.',
      )
    setBusy(false)
  }

  const updatePassword = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!supabase) return
    if (password !== passwordConfirm) {
      setError('Пароли не совпадают.')
      return
    }
    setBusy(true)
    setError('')
    const { error: updateError } = await supabase.auth.updateUser({ password })
    if (updateError)
      setError('Не удалось обновить пароль. Запросите новую ссылку для сброса.')
    else {
      setNotice('Пароль обновлён. Загружаем ваш аккаунт…')
      setPasswordConfirm('')
    }
    setBusy(false)
  }

  const chooseRole = async (nextRole: 'customer' | 'workshop') => {
    if (!supabase) return
    setBusy(true)
    setError('')
    const { data, error: roleError } = await supabase.rpc('choose_app_role', {
      p_role: nextRole,
    })
    if (roleError) setError('Не удалось сохранить роль. Попробуйте ещё раз.')
    else {
      setRole(data as AppRole)
      setScreen(data === 'workshop' ? 'workshop-onboarding' : 'home')
    }
    setBusy(false)
  }

  const signInWithTelegram = async () => {
    if (!supabase) return
    setBusy(true)
    setError('')
    const { error: authError } = await supabase.auth.signInWithOAuth({
      // Configure the Telegram OIDC provider in Supabase before enabling this button.
      provider: 'custom:telegram',
      options: { redirectTo: window.location.origin },
    })
    if (authError) {
      setError(
        'Telegram-вход пока не настроен в Supabase. Используйте вход по email.',
      )
      setBusy(false)
    }
  }

  const signOut = async () => {
    if (!supabase) return
    setBusy(true)
    const { error: signOutError } = await supabase.auth.signOut()
    if (signOutError) setError('Не удалось выйти. Попробуйте ещё раз.')
    else setEditingWorkshopProfile(false)
    setBusy(false)
  }

  const switchAuthMode = (mode: AuthMode) => {
    setAuthMode(mode)
    setPassword('')
    setPasswordConfirm('')
    setError('')
    setNotice('')
  }

  return (
    <main className="auth-page">
      <section className="auth-story" aria-label="О JewelMatch">
        <a className="brand" href="/" aria-label="JewelMatch — главная">
          <span className="brand-mark" aria-hidden="true">
            J
          </span>
          <span>JewelMatch</span>
        </a>
        <div className="story-copy">
          <p className="eyebrow">Ювелирное дело начинается с идеи</p>
          <h1>Находите мастеров, которые понимают ценность деталей.</h1>
          <p className="story-description">
            Пространство для тех, кто ищет своего ювелира, и мастерских, которые
            любят своё дело.
          </p>
        </div>
        <div className="story-foot">
          <span>01 / 03</span>
          <span>Соединяем идеи и мастерство</span>
        </div>
      </section>

      <section className="auth-panel" aria-labelledby="auth-title">
        <div className="panel-topline">
          <span>Частная платформа</span>
          <span className="availability">
            <i />
            Пилотный запуск
          </span>
        </div>

        {!isSupabaseConfigured ? (
          <div className="form-content">
            <p className="eyebrow">Подключение</p>
            <h2 id="auth-title">Нужно подключить Supabase</h2>
            <p className="muted">
              Скопируйте `.env.example` в `.env.local` и укажите URL проекта и
              публичный Publishable key.
            </p>
            <div className="setup-note">
              <span>01</span>
              <p>
                Запустите локальный Supabase и возьмите URL и Publishable key из
                `npx supabase status`.
              </p>
            </div>
            <div className="setup-note">
              <span>02</span>
              <p>Перезапустите Vite после сохранения `.env.local`.</p>
            </div>
          </div>
        ) : loading ? (
          <div className="form-content" aria-live="polite">
            <p className="eyebrow">Ваше пространство</p>
            <h2 id="auth-title">Загружаем профиль</h2>
            <div className="loading-line" />
          </div>
        ) : screen === 'auth' && !session ? (
          <div className="form-content">
            <p className="eyebrow">Ваше пространство</p>
            <h2 id="auth-title">
              {authMode === 'signin' ? 'Войдите в аккаунт' : 'Создайте аккаунт'}
            </h2>
            <p className="muted">
              {authMode === 'signin'
                ? 'Входите с электронной почтой и паролем.'
                : 'Зарегистрируйтесь, чтобы находить ювелиров или получать заказы.'}
            </p>
            <div
              className="auth-tabs"
              role="tablist"
              aria-label="Вход или регистрация"
            >
              <button
                type="button"
                role="tab"
                aria-selected={authMode === 'signin'}
                className={authMode === 'signin' ? 'active' : ''}
                onClick={() => switchAuthMode('signin')}
              >
                Вход
              </button>
              <button
                type="button"
                role="tab"
                aria-selected={authMode === 'signup'}
                className={authMode === 'signup' ? 'active' : ''}
                onClick={() => switchAuthMode('signup')}
              >
                Регистрация
              </button>
            </div>
            <form className="auth-form" onSubmit={handleAuth}>
              <div className="form-field">
                <label htmlFor="email">Электронная почта</label>
                <input
                  id="email"
                  type="email"
                  autoComplete="email"
                  placeholder="name@example.com"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  required
                />
              </div>
              <div className="form-field">
                <label htmlFor="password">Пароль</label>
                <input
                  id="password"
                  type="password"
                  autoComplete={
                    authMode === 'signin' ? 'current-password' : 'new-password'
                  }
                  minLength={8}
                  placeholder="Не менее 8 символов"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  required
                />
              </div>
              <button className="primary-button" type="submit" disabled={busy}>
                {busy
                  ? 'Подождите…'
                  : authMode === 'signin'
                    ? 'Войти'
                    : 'Создать аккаунт'}
                <span aria-hidden="true">↗</span>
              </button>
            </form>
            {authMode === 'signin' && (
              <button
                className="text-button forgot-button"
                type="button"
                disabled={busy}
                onClick={() => void sendPasswordReset()}
              >
                Забыли пароль?
              </button>
            )}
            {telegramEnabled && (
              <>
                <div className="divider">
                  <span>или</span>
                </div>
                <button
                  className="telegram-button"
                  type="button"
                  onClick={() => void signInWithTelegram()}
                  disabled={busy}
                >
                  <span className="telegram-icon" aria-hidden="true">
                    ➤
                  </span>
                  Продолжить с Telegram
                </button>
              </>
            )}
            <p className="fine-print">
              Продолжая, вы соглашаетесь с условиями использования и политикой
              конфиденциальности.
            </p>
          </div>
        ) : screen === 'confirm' && !session ? (
          <div className="form-content">
            <button
              className="back-button"
              type="button"
              onClick={() => {
                setScreen('auth')
                setError('')
                setNotice('')
              }}
            >
              ← Вернуться ко входу
            </button>
            <p className="eyebrow">Подтверждение почты</p>
            <h2 id="auth-title">Проверьте входящие</h2>
            <p className="muted">
              Мы отправили ссылку для подтверждения адреса{' '}
              <strong>{email}</strong>. Перейдите по ней, чтобы активировать
              аккаунт.
            </p>
            <button
              className="text-button"
              type="button"
              disabled={busy}
              onClick={() => void resendConfirmation()}
            >
              Отправить письмо повторно
            </button>
          </div>
        ) : screen === 'recovery' ? (
          <div className="form-content">
            <p className="eyebrow">Новый пароль</p>
            <h2 id="auth-title">Обновите пароль</h2>
            <p className="muted">
              Придумайте новый пароль не короче 8 символов.
            </p>
            <form className="auth-form" onSubmit={updatePassword}>
              <div className="form-field">
                <label htmlFor="password">Новый пароль</label>
                <input
                  id="password"
                  type="password"
                  autoComplete="new-password"
                  minLength={8}
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  required
                />
              </div>
              <div className="form-field">
                <label htmlFor="password-confirm">Повторите пароль</label>
                <input
                  id="password-confirm"
                  type="password"
                  autoComplete="new-password"
                  minLength={8}
                  value={passwordConfirm}
                  onChange={(event) => setPasswordConfirm(event.target.value)}
                  required
                />
              </div>
              <button className="primary-button" type="submit" disabled={busy}>
                {busy ? 'Сохраняем…' : 'Сохранить пароль'}
                <span aria-hidden="true">↗</span>
              </button>
            </form>
          </div>
        ) : screen === 'workshop-onboarding' && session ? (
          <WorkshopOnboarding
            session={session}
            showOptionalFields={editingWorkshopProfile}
            onComplete={() => {
              setEditingWorkshopProfile(false)
              setScreen('home')
            }}
          />
        ) : screen === 'role' && session ? (
          <div className="form-content">
            <p className="eyebrow">Первый шаг</p>
            <h2 id="auth-title">Как вы будете пользоваться JewelMatch?</h2>
            <p className="muted">
              Выбор закрепится за аккаунтом. Позже изменить его нельзя.
            </p>
            <div className="role-list">
              {(['customer', 'workshop'] as const).map((option, index) => (
                <button
                  className="role-card"
                  type="button"
                  disabled={busy}
                  onClick={() => void chooseRole(option)}
                  key={option}
                >
                  <span className="role-index">0{index + 1}</span>
                  <span className="role-copy">
                    <strong>{roleCopy[option].title}</strong>
                    <small>{roleCopy[option].detail}</small>
                  </span>
                  <span className="role-arrow" aria-hidden="true">
                    ↗
                  </span>
                </button>
              ))}
            </div>
          </div>
        ) : (
          <div className="form-content">
            <p className="eyebrow">Добро пожаловать</p>
            <h2 id="auth-title">
              {role === 'admin'
                ? 'Панель администратора'
                : roleCopy[role as 'customer' | 'workshop']?.title}
            </h2>
            <p className="muted">
              Вы вошли как{' '}
              <strong>{session?.user.email ?? 'пользователь Telegram'}</strong>.
            </p>
            <div className="setup-note">
              <span>✓</span>
              <p>
                {role === 'customer'
                  ? roleCopy.customer.detail
                  : role === 'workshop'
                    ? roleCopy.workshop.detail
                    : 'Управление платформой доступно администраторам.'}
              </p>
            </div>
            <button
              className="secondary-button"
              type="button"
              onClick={() => void signOut()}
              disabled={busy}
            >
              Выйти из аккаунта
            </button>
            {role === 'workshop' && (
              <button
                className="text-button"
                type="button"
                onClick={() => {
                  setEditingWorkshopProfile(true)
                  setScreen('workshop-onboarding')
                }}
              >
                Редактировать профиль мастерской
              </button>
            )}
          </div>
        )}

        <div className="form-feedback" aria-live="polite">
          {error && <p className="error-message">{error}</p>}
          {notice && <p className="success-message">{notice}</p>}
        </div>
        <footer className="panel-footer">
          <span>© 2026 JewelMatch</span>
          <span>Создано с вниманием к деталям</span>
        </footer>
      </section>
    </main>
  )
}
