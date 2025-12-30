# Converting Diagrams to Word Document Format

## Generated Diagrams

Three diagram files have been created for use in Word documents:

### 1. HPC Architecture Diagram
- **File**: `hpc-architecture.png` (232KB)
- **Description**: Complete AWS architecture with all components
- **Use**: Main architecture figure for blog post
- **Format**: PNG, high resolution

### 2. Data Flow Diagram (Detailed)
- **File**: `dataflow-diagram.png` (171KB)
- **Description**: 5-stage flow with clusters and detailed labels
- **Use**: Detailed process flow documentation
- **Format**: PNG, high resolution

### 3. Data Flow Diagram (Simple)
- **File**: `dataflow-simple.png` (44KB)
- **Description**: Compact linear flow matching ASCII style
- **Use**: Blog post, presentations, quick reference
- **Format**: PNG, optimized for web and print

## Inserting into Word Document

### Method 1: Direct Insert (Recommended)

1. **Open Microsoft Word**
2. **Insert → Pictures → Picture from File**
3. **Navigate to**: `/Users/spereirj/dynamic_allocation/docs/diagrams/`
4. **Select**: The PNG file you want to insert
5. **Click Insert**

### Method 2: Drag and Drop

1. **Open Finder** and navigate to `docs/diagrams/`
2. **Open Microsoft Word** document
3. **Drag the PNG file** directly into the Word document
4. **Resize as needed**

## Formatting in Word

### Resize the Image
1. Click on the inserted image
2. Drag corner handles to resize (hold Shift to maintain aspect ratio)
3. Or right-click → Size and Position → Set specific dimensions

### Add Caption
1. Right-click on image → Insert Caption
2. **For Architecture**: "Figure 1: ML-Driven HPC Resource Optimization System Architecture"
3. **For Data Flow**: "Figure 2: ML-Driven Resource Optimization Flow"

### Text Wrapping
1. Click on image
2. Layout Options (icon appears next to image)
3. Select "In Line with Text" or "Square" depending on layout needs

### Center the Image
1. Click on image
2. Home tab → Paragraph section → Center align
3. Or Ctrl+E (Windows) / Cmd+E (Mac)

## Recommended Settings for Blog Post

### Architecture Diagram (hpc-architecture.png)
- **Width**: 6.5 inches (full page width)
- **Position**: Centered
- **Caption**: "Figure 1: ML-Driven HPC Resource Optimization System Architecture"
- **Text Wrapping**: In Line with Text

### Data Flow Diagram (dataflow-simple.png)
- **Width**: 6.0 inches
- **Position**: Centered
- **Caption**: "Figure 2: ML-Driven Resource Optimization Flow"
- **Text Wrapping**: In Line with Text

## Quality Settings

All diagrams are generated at high resolution suitable for:
- ✓ Web publication (blogs, documentation sites)
- ✓ Print publication (whitepapers, reports)
- ✓ Presentations (PowerPoint, Keynote)
- ✓ PDF export

## Alternative: Export to PDF

If you need PDF format:

```bash
# Convert PNG to PDF using Preview (Mac)
open docs/diagrams/hpc-architecture.png
# File → Export as PDF

# Or use command line (requires ImageMagick)
convert docs/diagrams/hpc-architecture.png docs/diagrams/hpc-architecture.pdf
```

## Alternative: Export to SVG

For vector graphics (scalable without quality loss):

```bash
# Regenerate with SVG output
# Edit the Python script and change:
# outformat="png"  →  outformat="svg"
```

## Troubleshooting

### Image appears blurry in Word
- Ensure you're using the original PNG file (not a screenshot)
- Don't resize beyond 100% of original size
- Use "High Quality" print settings in Word

### Image is too large
- Use the "simple" version (44KB vs 171KB)
- Or compress in Word: Picture Format → Compress Pictures

### Colors look different
- PNG files use RGB color space
- For print, consider converting to CMYK in Photoshop/GIMP

## Files Location

All diagram files are in:
```
/Users/spereirj/dynamic_allocation/docs/diagrams/
```

Contents:
- `hpc-architecture.png` - Main AWS architecture
- `dataflow-diagram.png` - Detailed 5-stage flow
- `dataflow-simple.png` - Compact flow diagram
- `README.md` - Generation instructions
- `VALIDATION_CHECKLIST.md` - Quality checklist
- `WORD_DOCUMENT_GUIDE.md` - This guide
