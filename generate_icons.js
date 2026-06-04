const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

// SVG definition for Dark Icon (Default)
const darkSvg = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <rect width="1024" height="1024" fill="#0f172a" />
  <text x="512" y="520" 
        font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Helvetica, Arial, sans-serif" 
        font-size="580" 
        font-weight="800" 
        text-anchor="middle" 
        dominant-baseline="central"
        letter-spacing="-15">
    <tspan fill="#ffffff">P</tspan><tspan fill="#3b82f6" dx="5">L</tspan>
  </text>
</svg>
`;

// SVG definition for Light Icon
const lightSvg = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <rect width="1024" height="1024" fill="#f8fafc" />
  <text x="512" y="520" 
        font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Helvetica, Arial, sans-serif" 
        font-size="580" 
        font-weight="800" 
        text-anchor="middle" 
        dominant-baseline="central"
        letter-spacing="-15">
    <tspan fill="#0f172a">P</tspan><tspan fill="#3b82f6" dx="5">L</tspan>
  </text>
</svg>
`;

async function generate() {
  const baseDir = __dirname;
  const assetsDir = path.join(baseDir, 'PrivateLift', 'Assets.xcassets', 'AppIcon.appiconset');

  console.log('Writing SVG files...');
  fs.writeFileSync(path.join(baseDir, 'dark.svg'), darkSvg.trim());
  fs.writeFileSync(path.join(baseDir, 'light.svg'), lightSvg.trim());

  console.log('Generating PNG files using sharp...');
  
  // Generate dark.png (Universal / Default)
  await sharp(Buffer.from(darkSvg))
    .png()
    .toFile(path.join(baseDir, 'dark.png'));
  console.log('Generated dark.png in project root');

  // Generate light.png
  await sharp(Buffer.from(lightSvg))
    .png()
    .toFile(path.join(baseDir, 'light.png'));
  console.log('Generated light.png in project root');

  // Generate target assets
  // 1. AppIcon.appiconset/dark.png (Default universal)
  await sharp(Buffer.from(darkSvg))
    .png()
    .toFile(path.join(assetsDir, 'dark.png'));
  console.log('Generated AppIcon.appiconset/dark.png');

  // 2. AppIcon.appiconset/dark 1.png (Dark appearance)
  await sharp(Buffer.from(darkSvg))
    .png()
    .toFile(path.join(assetsDir, 'dark 1.png'));
  console.log('Generated AppIcon.appiconset/dark 1.png');

  // 3. AppIcon.appiconset/light.png (Light appearance / Tinted)
  await sharp(Buffer.from(lightSvg))
    .png()
    .toFile(path.join(assetsDir, 'light.png'));
  console.log('Generated AppIcon.appiconset/light.png');

  console.log('All icons generated successfully!');
}

generate().catch(err => {
  console.error('Error generating icons:', err);
  process.exit(1);
});
