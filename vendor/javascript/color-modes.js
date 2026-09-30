/*!
 * https://getbootstrap.com/docs/5.3/assets/js/color-modes.js
 * Modified to use font icons (instead of SVG), and for Turbo (which replaces the page body on each visit)
 *
 *
 * Color mode toggler for Bootstrap's docs (https://getbootstrap.com/)
 * Copyright 2011-2024 The Bootstrap Authors
 * Licensed under the Creative Commons Attribution 3.0 Unported License.
 */

(() => {
  'use strict'

  const getStoredTheme = () => localStorage.getItem('theme')
  const setStoredTheme = theme => localStorage.setItem('theme', theme)

  const getPreferredTheme = () => {
    const storedTheme = getStoredTheme()
    if (storedTheme) {
      return storedTheme
    }
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  }

  const setTheme = theme => {
    if (theme === 'auto') {
      document.documentElement.setAttribute('data-bs-theme', (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'))
    } else {
      document.documentElement.setAttribute('data-bs-theme', theme)
    }
  }

  setTheme(getPreferredTheme())

  const showActiveTheme = (theme, focus = false) => {
    const themeSwitcher = document.querySelector('#bd-theme')
    if (!themeSwitcher) return

    const themeSwitcherText = document.querySelector('#bd-theme-text')
    const activeThemeEl = document.querySelector('.theme-icon-active')
    const activeThemeOption = document.querySelector(`[data-bs-theme-value="${theme}"]`)

    document.querySelectorAll('[data-bs-theme-value]').forEach(element => {
      element.classList.remove('active')
      element.setAttribute('aria-pressed', 'false')
    })
    activeThemeOption.classList.add('active')
    activeThemeOption.setAttribute('aria-pressed', 'true')

    if ( theme == 'auto' )  activeThemeEl.classList.add('bi-circle-half');     else activeThemeEl.classList.remove('bi-circle-half')
    if ( theme == 'light' ) activeThemeEl.classList.add('bi-sun-fill');        else activeThemeEl.classList.remove('bi-sun-fill')
    if ( theme == 'dark' )  activeThemeEl.classList.add('bi-moon-stars-fill'); else activeThemeEl.classList.remove('bi-moon-stars-fill')

    const themeSwitcherLabel = `${themeSwitcherText.textContent} (${activeThemeOption.dataset.bsThemeValue})`
    themeSwitcher.setAttribute('aria-label', themeSwitcherLabel)

    if (focus) themeSwitcher.focus()
  }

  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    const storedTheme = getStoredTheme()
    if (storedTheme !== 'light' && storedTheme !== 'dark') {
      setTheme(getPreferredTheme())
    }
  })

  document.addEventListener('turbo:load', () => showActiveTheme(getPreferredTheme()))

  document.addEventListener('click', event => {
    const toggle = event.target.closest('[data-bs-theme-value]')
    if (!toggle) return

    const theme = toggle.getAttribute('data-bs-theme-value')
    setStoredTheme(theme)
    setTheme(theme)
    showActiveTheme(theme, true)
  })
})()
