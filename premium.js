(function () {
  'use strict';

  // ═══════════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════════
  const CONFIG = {
    API_BASE_URL: 'https://api.pecu.tools',
    ENDPOINTS: {
      VALIDATE: '/api/v1/license/validate',
      HEALTH: '/api/v1/health'
    },
    TIMEOUT: 30000, // 30 seconds
    RETRY_ATTEMPTS: 3,
    RETRY_DELAY: 1000, // 1 second
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // UTILITY FUNCTIONS
  // ═══════════════════════════════════════════════════════════════════════════════
  const Utils = {
    // Format license key with dashes
    formatLicenseKey: (key) => {
      const cleaned = key.replace(/[^A-Z0-9]/g, '');
      if (cleaned.length <= 4) return cleaned;
      
      const formatted = cleaned.match(/.{1,4}/g).join('-');
      return formatted.toUpperCase();
    },

    // Validate license key format
    isValidLicenseFormat: (key) => {
      const pattern = /^PECU-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/;
      return pattern.test(key.toUpperCase());
    },

    // Get URL parameters
    getUrlParams: () => {
      const params = new URLSearchParams(window.location.search);
      return {
        license: params.get('license'),
        email: params.get('email'),
        order_id: params.get('order_id')
      };
    },

    // Format date
    formatDate: (dateString) => {
      if (!dateString) return '—';
      try {
        return new Date(dateString).toLocaleDateString('en-US', {
          year: 'numeric',
          month: 'long',
          day: 'numeric'
        });
      } catch (e) {
        return '—';
      }
    },

    // Debounce function
    debounce: (func, wait) => {
      let timeout;
      return function executedFunction(...args) {
        const later = () => {
          clearTimeout(timeout);
          func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
      };
    },

    // Sleep function
    sleep: (ms) => new Promise(resolve => setTimeout(resolve, ms)),

    // Copy to clipboard
    copyToClipboard: async (text) => {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch (err) {
        // Fallback for older browsers
        const textarea = document.createElement('textarea');
        textarea.value = text;
        textarea.style.position = 'fixed';
        textarea.style.opacity = '0';
        document.body.appendChild(textarea);
        textarea.select();
        const success = document.execCommand('copy');
        document.body.removeChild(textarea);
        return success;
      }
    }
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // API CLIENT
  // ═══════════════════════════════════════════════════════════════════════════════
  const ApiClient = {
    // Make HTTP request with retry logic
    async request(endpoint, options = {}) {
      const url = CONFIG.API_BASE_URL + endpoint;
      const defaultOptions = {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'PECU-Web/1.0'
        },
        timeout: CONFIG.TIMEOUT
      };

      const requestOptions = { ...defaultOptions, ...options };

      for (let attempt = 1; attempt <= CONFIG.RETRY_ATTEMPTS; attempt++) {
        try {
          const controller = new AbortController();
          const timeoutId = setTimeout(() => controller.abort(), requestOptions.timeout);

          const response = await fetch(url, {
            ...requestOptions,
            signal: controller.signal
          });

          clearTimeout(timeoutId);

          if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
          }

          const data = await response.json();
          return { success: true, data, status: response.status };

        } catch (error) {
          console.warn(`API request attempt ${attempt} failed:`, error.message);

          if (attempt === CONFIG.RETRY_ATTEMPTS) {
            return {
              success: false,
              error: error.name === 'AbortError' ? 'Request timeout' : error.message,
              status: 0
            };
          }

          // Wait before retry
          await Utils.sleep(CONFIG.RETRY_DELAY * attempt);
        }
      }
    },

    // Validate license
    async validateLicense(licenseKey, hardwareHash = 'browser-check') {
      const response = await this.request(CONFIG.ENDPOINTS.VALIDATE, {
        method: 'POST',
        body: JSON.stringify({
          license_key: licenseKey,
          hardware_hash: hardwareHash
        })
      });

      return response;
    },

    // Check API health
    async checkHealth() {
      const response = await this.request(CONFIG.ENDPOINTS.HEALTH);
      return response;
    }
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // UI MANAGER
  // ═══════════════════════════════════════════════════════════════════════════════
  const UI = {
    elements: {},

    // Initialize DOM references
    init() {
      this.elements = {
        licenseInput: document.getElementById('license-input'),
        validateBtn: document.getElementById('validate-btn'),
        validationResult: document.getElementById('validation-result'),
        licenseForm: document.getElementById('license-form')
      };

      // Check for missing elements
      Object.entries(this.elements).forEach(([key, element]) => {
        if (!element) {
          console.error(`Element not found: ${key}`);
        }
      });
    },

    // Show loading state
    showLoading(message = 'Validating license...') {
      this.elements.validateBtn.disabled = true;
      this.elements.validateBtn.innerHTML = `
        <i class="fas fa-spinner fa-spin"></i>
        ${message}
      `;

      this.showMessage(message, 'loading');
    },

    // Hide loading state
    hideLoading() {
      this.elements.validateBtn.disabled = false;
      this.elements.validateBtn.innerHTML = `
        <i class="fas fa-check-circle"></i>
        Validate License
      `;
    },

    // Show message
    showMessage(message, type = 'info') {
      const iconMap = {
        success: 'fas fa-check-circle',
        error: 'fas fa-exclamation-triangle',
        loading: 'fas fa-spinner fa-spin',
        info: 'fas fa-info-circle'
      };

      this.elements.validationResult.innerHTML = `
        <div class="status-message status-${type}">
          <i class="${iconMap[type]}"></i>
          <div style="margin-left: 8px;">${message}</div>
        </div>
      `;
    },

    // Show validation success
    showValidationSuccess(data) {
      const user = data.user || {};
      const plan = user.plan || 'Unknown';
      const downloadsRemaining = data.downloads_remaining ?? '∞';
      const expiryDate = Utils.formatDate(data.expiry_date);
      const features = data.features || [];

      const featuresList = features.length > 0 
        ? `<br><br><strong>Available Features:</strong><br>${features.map(f => `• ${f}`).join('<br>')}`
        : '';

      const message = `
        <strong>✓ License Valid!</strong><br>
        <strong>Plan:</strong> ${plan}<br>
        <strong>Downloads Remaining:</strong> ${downloadsRemaining}<br>
        <strong>Expires:</strong> ${expiryDate}${featuresList}
      `;

      this.showMessage(message, 'success');
    },

    // Show validation error
    showValidationError(error) {
      const errorMessages = {
        'License not found': 'The license key you entered was not found. Please check your email receipt and try again.',
        'License expired': 'Your license has expired. Please renew your subscription to continue using premium features.',
        'License inactive': 'Your license is not active. Please contact support if you believe this is an error.',
        'Invalid hardware': 'This license is registered to a different hardware. Contact support to transfer your license.',
        'Rate limit exceeded': 'Too many validation attempts. Please wait a moment and try again.',
        'Request timeout': 'The validation request timed out. Please check your internet connection and try again.',
        'Network error': 'Unable to connect to the license server. Please check your internet connection and try again.'
      };

      const message = errorMessages[error] || `Validation failed: ${error}`;
      this.showMessage(message, 'error');
    },

    // Format license input
    formatLicenseInput() {
      const input = this.elements.licenseInput;
      const cursorPos = input.selectionStart;
      const oldValue = input.value;
      const newValue = Utils.formatLicenseKey(oldValue);
      
      if (oldValue !== newValue) {
        input.value = newValue;
        
        // Restore cursor position accounting for added dashes
        const addedChars = newValue.length - oldValue.length;
        const newCursorPos = Math.min(cursorPos + addedChars, newValue.length);
        input.setSelectionRange(newCursorPos, newCursorPos);
      }
    },

    // Setup copy buttons
    setupCopyButtons() {
      document.addEventListener('click', async (e) => {
        const copyBtn = e.target.closest('.copy-button');
        if (!copyBtn) return;

        const command = copyBtn.dataset.command;
        if (!command) return;

        const success = await Utils.copyToClipboard(command);
        
        if (success) {
          const originalIcon = copyBtn.innerHTML;
          copyBtn.innerHTML = '<i class="fas fa-check" style="color: var(--pecu-green);"></i>';
          setTimeout(() => {
            copyBtn.innerHTML = originalIcon;
          }, 2000);
        }
      });
    }
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // LICENSE VALIDATOR
  // ═══════════════════════════════════════════════════════════════════════════════
  const LicenseValidator = {
    // Validate license
    async validate(licenseKey) {
      // Format and validate input
      const formattedKey = Utils.formatLicenseKey(licenseKey);
      
      if (!Utils.isValidLicenseFormat(formattedKey)) {
        throw new Error('Invalid license key format. Please check your license key and try again.');
      }

      // Make API request
      const response = await ApiClient.validateLicense(formattedKey);
      
      if (!response.success) {
        throw new Error(response.error || 'Network error');
      }

      const data = response.data;
      
      if (!data.valid) {
        throw new Error(data.error || 'Invalid license');
      }

      return data;
    }
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // APPLICATION MAIN
  // ═══════════════════════════════════════════════════════════════════════════════
  const App = {
    // Initialize application
    async init() {
      console.log('PECU Premium License Validator v1.0');
      
      // Initialize UI
      UI.init();
      UI.setupCopyButtons();

      // Setup event listeners
      this.setupEventListeners();

      // Pre-fill license from URL if present
      this.prefillLicenseFromUrl();

      // Check API health
      this.checkApiHealth();
    },

    // Setup event listeners
    setupEventListeners() {
      const { licenseInput, validateBtn } = UI.elements;

      // Format license input as user types
      licenseInput.addEventListener('input', Utils.debounce(() => {
        UI.formatLicenseInput();
      }, 100));

      // Validate on button click
      validateBtn.addEventListener('click', () => {
        this.handleValidation();
      });

      // Validate on Enter key
      licenseInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          this.handleValidation();
        }
      });

      // Clear validation result when user starts typing
      licenseInput.addEventListener('input', () => {
        if (UI.elements.validationResult.innerHTML) {
          UI.elements.validationResult.innerHTML = '';
        }
      });
    },

    // Pre-fill license from URL parameters
    prefillLicenseFromUrl() {
      const { license } = Utils.getUrlParams();
      if (license) {
        UI.elements.licenseInput.value = Utils.formatLicenseKey(license);
        
        // Auto-validate if license is pre-filled and looks valid
        if (Utils.isValidLicenseFormat(Utils.formatLicenseKey(license))) {
          setTimeout(() => this.handleValidation(), 1000);
        }
      }
    },

    // Handle license validation
    async handleValidation() {
      const licenseKey = UI.elements.licenseInput.value.trim();
      
      if (!licenseKey) {
        UI.showMessage('Please enter your license key.', 'error');
        UI.elements.licenseInput.focus();
        return;
      }

      try {
        UI.showLoading('Validating license...');
        
        const validationData = await LicenseValidator.validate(licenseKey);
        
        UI.hideLoading();
        UI.showValidationSuccess(validationData);
        
        // Analytics (optional)
        this.trackEvent('license_validation_success');

      } catch (error) {
        console.error('License validation error:', error);
        UI.hideLoading();
        UI.showValidationError(error.message);
        
        // Analytics (optional)
        this.trackEvent('license_validation_error', { error: error.message });
      }
    },

    // Check API health
    async checkApiHealth() {
      try {
        const response = await ApiClient.checkHealth();
        if (response.success) {
          console.log('API health check: OK');
        } else {
          console.warn('API health check failed:', response.error);
        }
      } catch (error) {
        console.warn('API health check error:', error);
      }
    },

    // Track events (placeholder for analytics)
    trackEvent(eventName, properties = {}) {
      // Here you could integrate with analytics services like:
      // - Google Analytics 4
      // - Mixpanel
      // - PostHog
      // - Custom analytics
      
      console.log('Event tracked:', eventName, properties);
      
      // Example GA4 integration:
      // if (typeof gtag !== 'undefined') {
      //   gtag('event', eventName, properties);
      // }
    }
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // APPLICATION STARTUP
  // ═══════════════════════════════════════════════════════════════════════════════
  
  // Start application when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', App.init.bind(App));
  } else {
    App.init();
  }

  // Global error handler
  window.addEventListener('error', (event) => {
    console.error('Global error:', event.error);
    // Could send error reports to monitoring service
  });

  // Unhandled promise rejection handler
  window.addEventListener('unhandledrejection', (event) => {
    console.error('Unhandled promise rejection:', event.reason);
    // Could send error reports to monitoring service
  });

  // Export for debugging (only in development)
  if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
    window.PECU_Premium = {
      App,
      UI,
      ApiClient,
      LicenseValidator,
      Utils,
      CONFIG
    };
  }

})();
