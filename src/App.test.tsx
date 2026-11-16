import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App from './App'

const { auth, subscription } = vi.hoisted(() => ({
  auth: {
    getSession: vi.fn(),
    onAuthStateChange: vi.fn(),
    signUp: vi.fn(),
    signInWithPassword: vi.fn(),
    resend: vi.fn(),
    resetPasswordForEmail: vi.fn(),
    updateUser: vi.fn(),
    signOut: vi.fn(),
    signInWithOAuth: vi.fn(),
  },
  subscription: { unsubscribe: vi.fn() },
}))

vi.mock('./lib/supabase', () => ({
  isSupabaseConfigured: true,
  supabase: { auth },
}))

describe('App authentication entry', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    auth.getSession.mockResolvedValue({ data: { session: null } })
    auth.onAuthStateChange.mockReturnValue({
      data: { subscription },
    })
    auth.signUp.mockResolvedValue({
      data: { session: null },
      error: null,
    })
  })

  it('shows a registration confirmation after signup', async () => {
    const user = userEvent.setup()
    render(<App />)

    await screen.findByRole('heading', { name: 'Войдите в аккаунт' })
    await user.click(screen.getByRole('tab', { name: 'Регистрация' }))
    await user.type(
      screen.getByLabelText('Электронная почта'),
      'client@example.com',
    )
    await user.type(screen.getByLabelText('Пароль'), 'secure-pass-123')
    await user.click(screen.getByRole('button', { name: 'Создать аккаунт' }))

    expect(
      await screen.findByRole('heading', { name: 'Проверьте входящие' }),
    ).toBeInTheDocument()
    expect(auth.signUp).toHaveBeenCalledWith({
      email: 'client@example.com',
      password: 'secure-pass-123',
      options: { emailRedirectTo: window.location.origin },
    })
  })
})
