/**
 * Input Validation Schemas and Middleware
 * Phase 2: Security Enhancement
 * 
 * Uses Joi for schema validation with:
 * - Type checking
 * - Length limits
 * - Format validation
 * - Sanitization (trim, normalize)
 */

const Joi = require('joi');

// =============================================================================
// Validation Schemas
// =============================================================================

/**
 * Chat endpoint schema
 * POST /chat
 */
const chatSchema = Joi.object({
  message: Joi.string().trim().min(1).max(2000).required()
    .messages({
      'string.empty': 'Message cannot be empty',
      'string.max': 'Message cannot exceed 2000 characters',
      'any.required': 'Message is required'
    }),
  conversation_history: Joi.array().items(
    Joi.object({
      role: Joi.string().valid('user', 'assistant', 'system').required(),
      content: Joi.string().max(4000).required()
    })
  ).max(20).optional(),
  userFirstName: Joi.string().trim().max(50).allow('', null).optional(),
  userPreferences: Joi.object().unknown(true).optional(),
  userPoints: Joi.number().integer().min(0).optional()
});

/**
 * Combo generation schema
 * POST /generate-combo
 */
const comboSchema = Joi.object({
  userName: Joi.string().trim().min(1).max(50).required()
    .messages({
      'string.empty': 'User name is required',
      'any.required': 'User name is required'
    }),
  dietaryPreferences: Joi.object({
    spiceLevel: Joi.string().valid('none', 'mild', 'medium', 'spicy', '').allow(null).optional(),
    allergies: Joi.array().items(Joi.string().max(50)).max(20).optional(),
    isVegetarian: Joi.boolean().optional(),
    isVegan: Joi.boolean().optional(),
    isGlutenFree: Joi.boolean().optional(),
    noPork: Joi.boolean().optional(),
    noBeef: Joi.boolean().optional(),
    noSeafood: Joi.boolean().optional()
  }).unknown(true).optional(),
  menuItems: Joi.array().optional(),
  previousRecommendations: Joi.array().max(50).optional()
});

/**
 * Referral accept schema
 * POST /referrals/accept
 */
const referralAcceptSchema = Joi.object({
  code: Joi.string().trim().uppercase().alphanum().length(6).required()
    .messages({
      'string.empty': 'Referral code is required',
      'string.alphanum': 'Referral code must contain only letters and numbers',
      'string.length': 'Referral code must be exactly 6 characters',
      'any.required': 'Referral code is required'
    }),
  deviceId: Joi.string().max(100).allow('', null).optional()
});

/**
 * Admin user update schema
 * POST /admin/users/update
 */
const adminUserUpdateSchema = Joi.object({
  userId: Joi.string().trim().min(1).max(128).required()
    .messages({
      'string.empty': 'User ID is required',
      'any.required': 'User ID is required'
    }),
  points: Joi.number().integer().min(0).max(1000000).optional(),
  phone: Joi.string().max(20).allow('', null).optional(),
  isAdmin: Joi.boolean().optional(),
  isVerified: Joi.boolean().optional()
});

/**
 * Reward redemption schema
 * POST /redeem-reward
 */
const redeemRewardSchema = Joi.object({
  userId: Joi.string().max(128).allow('', null).optional(),
  rewardTitle: Joi.string().trim().max(200).required()
    .messages({
      'string.empty': 'Reward title is required',
      'any.required': 'Reward title is required'
    }),
  rewardDescription: Joi.string().max(500).allow('', null).optional(),
  pointsRequired: Joi.number().integer().min(0).max(100000).required()
    .messages({
      'number.base': 'Points required must be a number',
      'any.required': 'Points required is required'
    }),
  rewardCategory: Joi.string().max(50).allow('', null).optional(),
  idempotencyKey: Joi.string().max(100).allow('', null).optional(),
  selectedItemId: Joi.string().max(100).allow('', null).optional(),
  selectedItemName: Joi.string().max(200).allow('', null).optional(),
  selectedToppingId: Joi.string().max(100).allow('', null).optional(),
  selectedToppingName: Joi.string().max(200).allow('', null).optional(),
  selectedItemId2: Joi.string().max(100).allow('', null).optional(),
  selectedItemName2: Joi.string().max(200).allow('', null).optional(),
  cookingMethod: Joi.string().max(50).allow('', null).optional(),
  drinkType: Joi.string().max(50).allow('', null).optional(),
  selectedDrinkItemId: Joi.string().max(100).allow('', null).optional(),
  selectedDrinkItemName: Joi.string().max(200).allow('', null).optional()
});

// =============================================================================
// Validation Middleware
// =============================================================================

/**
 * Creates validation middleware for a given schema
 * @param {Joi.Schema} schema - Joi schema to validate against
 * @returns {Function} Express middleware function
 */
function validate(schema) {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.body, {
      abortEarly: false,      // Report all errors, not just the first
      stripUnknown: false,    // Don't remove unknown fields (preserve existing behavior)
      convert: true           // Allow type coercion (e.g., string "123" to number 123)
    });

    if (error) {
      const messages = error.details.map(d => d.message).join(', ');
      console.log('❌ Validation failed:', messages);
      return res.status(400).json({
        errorCode: 'VALIDATION_ERROR',
        error: `Validation failed: ${messages}`
      });
    }

    // Replace body with validated/sanitized values
    req.body = value;
    next();
  };
}

// =============================================================================
// Sanitization Helpers
// =============================================================================

/**
 * Basic HTML entity encoding for user-generated text
 * Prevents XSS when content is rendered in web contexts
 * @param {string} text - Input text to sanitize
 * @returns {string} Sanitized text with HTML entities encoded
 */
function sanitizeText(text) {
  if (typeof text !== 'string') return text;
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;');
}

/**
 * Sanitize an object's string values recursively
 * @param {Object} obj - Object to sanitize
 * @returns {Object} Sanitized object
 */
function sanitizeObject(obj) {
  if (typeof obj !== 'object' || obj === null) {
    return typeof obj === 'string' ? sanitizeText(obj) : obj;
  }

  if (Array.isArray(obj)) {
    return obj.map(sanitizeObject);
  }

  const sanitized = {};
  for (const [key, value] of Object.entries(obj)) {
    sanitized[key] = sanitizeObject(value);
  }
  return sanitized;
}

// =============================================================================
// Exports
// =============================================================================

module.exports = {
  // Schemas
  chatSchema,
  comboSchema,
  referralAcceptSchema,
  adminUserUpdateSchema,
  redeemRewardSchema,
  
  // Middleware
  validate,
  
  // Helpers
  sanitizeText,
  sanitizeObject
};
