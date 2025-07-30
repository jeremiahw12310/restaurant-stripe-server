# GPT Model Pricing Comparison for Receipt Scanning

## Current Models and Pricing (as of 2024)

### GPT-4o (Previous Model)
- **Input**: $5.00 per 1M tokens
- **Output**: $15.00 per 1M tokens
- **Image Input**: $2.50 per 1M tokens
- **Best for**: General purpose tasks

### GPT-4 Vision Preview (Current Model)
- **Input**: $10.00 per 1M tokens  
- **Output**: $30.00 per 1M tokens
- **Image Input**: $5.00 per 1M tokens
- **Best for**: Vision and image analysis tasks

### GPT-4 Turbo (Alternative Option)
- **Input**: $10.00 per 1M tokens
- **Output**: $30.00 per 1M tokens
- **Image Input**: $5.00 per 1M tokens
- **Best for**: Latest capabilities, good for vision

## Cost Analysis for Receipt Scanning

### Typical Receipt Scan:
- **Image**: ~1-2 tokens
- **Prompt**: ~500-800 tokens
- **Response**: ~100-200 tokens
- **Total per scan**: ~600-1000 tokens

### Cost per Receipt Scan:
- **GPT-4o**: ~$0.002-0.004 per scan
- **GPT-4 Vision Preview**: ~$0.004-0.008 per scan
- **GPT-4 Turbo**: ~$0.004-0.008 per scan

### With Double Validation (2 scans):
- **GPT-4o**: ~$0.004-0.008 per receipt
- **GPT-4 Vision Preview**: ~$0.008-0.016 per receipt
- **GPT-4 Turbo**: ~$0.008-0.016 per receipt

## Recommendation

**GPT-4 Vision Preview** is about **2x more expensive** than GPT-4o, but provides:
- ✅ Better accuracy for receipt scanning
- ✅ Reduced error rates
- ✅ Better handling of unclear images
- ✅ More consistent results

**Cost Impact**: ~$0.008-0.016 per receipt (very reasonable for the accuracy improvement)

## Alternative: Hybrid Approach
We could use:
- **GPT-4o** for clear receipts (cheaper)
- **GPT-4 Vision Preview** for unclear receipts (better accuracy)
- **Fallback logic** to retry with vision model if first scan fails 