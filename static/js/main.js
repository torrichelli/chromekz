// Main JavaScript functionality for Hrom KZ logistics system

// Function to show forms
function showForm(formId) {
    // Hide all forms first
    hideAllForms();
    
    // Show the requested form
    const form = document.getElementById(formId);
    if (form) {
        form.style.display = 'block';
        form.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
}

// Function to hide a specific form
function hideForm(formId) {
    const form = document.getElementById(formId);
    if (form) {
        form.style.display = 'none';
    }
}

// Function to hide all forms
function hideAllForms() {
    const forms = document.querySelectorAll('.form-container');
    forms.forEach(form => {
        form.style.display = 'none';
    });
}

// Function to show request details (for dashboard)
function showRequestDetails(requestId) {
    console.log('Showing details for request:', requestId);
    // Modal is handled by Bootstrap, this function can be extended for additional logic
}

// Form validation
document.addEventListener('DOMContentLoaded', function() {
    // Add form validation for phone numbers
    const phoneInputs = document.querySelectorAll('input[id*="phone"]');
    phoneInputs.forEach(input => {
        input.addEventListener('input', function(e) {
            // Remove non-numeric characters except +, -, (, ), and spaces
            let value = e.target.value.replace(/[^\d\+\-\(\)\s]/g, '');
            e.target.value = value;
        });
    });

    // Add form validation for weight and volume (only positive numbers)
    const numericInputs = document.querySelectorAll('input[id*="weight"], input[id*="volume"]');
    numericInputs.forEach(input => {
        input.addEventListener('input', function(e) {
            // Allow only numbers and decimal point
            let value = e.target.value.replace(/[^\d\.]/g, '');
            
            // Ensure only one decimal point
            const parts = value.split('.');
            if (parts.length > 2) {
                value = parts[0] + '.' + parts.slice(1).join('');
            }
            
            e.target.value = value;
        });
    });

    // Auto-dismiss alerts after 5 seconds
    const alerts = document.querySelectorAll('.alert');
    alerts.forEach(alert => {
        setTimeout(() => {
            const closeBtn = alert.querySelector('.btn-close');
            if (closeBtn) {
                closeBtn.click();
            }
        }, 5000);
    });

    // Add loading state to form submissions
    const forms = document.querySelectorAll('form');
    forms.forEach(form => {
        form.addEventListener('submit', function(e) {
            const submitBtn = form.querySelector('input[type="submit"], button[type="submit"]');
            if (submitBtn) {
                submitBtn.disabled = true;
                submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin me-2"></i>Отправка...';
                
                // Re-enable after 3 seconds in case of error
                setTimeout(() => {
                    submitBtn.disabled = false;
                    submitBtn.innerHTML = submitBtn.getAttribute('data-original-text') || 'Отправить';
                }, 3000);
            }
        });
    });

    // Store original button text
    const submitButtons = document.querySelectorAll('input[type="submit"], button[type="submit"]');
    submitButtons.forEach(btn => {
        btn.setAttribute('data-original-text', btn.value || btn.textContent);
    });
});

// Utility function to format phone numbers (Kazakhstan format)
function formatPhoneNumber(phone) {
    // Remove all non-numeric characters
    const cleaned = phone.replace(/\D/g, '');
    
    // Format as +7 (XXX) XXX-XX-XX
    if (cleaned.length === 11 && cleaned.startsWith('7')) {
        return `+7 (${cleaned.slice(1, 4)}) ${cleaned.slice(4, 7)}-${cleaned.slice(7, 9)}-${cleaned.slice(9, 11)}`;
    } else if (cleaned.length === 10) {
        return `+7 (${cleaned.slice(0, 3)}) ${cleaned.slice(3, 6)}-${cleaned.slice(6, 8)}-${cleaned.slice(8, 10)}`;
    }
    
    return phone; // Return original if doesn't match expected format
}

// Add phone formatting on blur
document.addEventListener('DOMContentLoaded', function() {
    const phoneInputs = document.querySelectorAll('input[id*="phone"]');
    phoneInputs.forEach(input => {
        input.addEventListener('blur', function(e) {
            if (e.target.value) {
                e.target.value = formatPhoneNumber(e.target.value);
            }
        });
    });
});
