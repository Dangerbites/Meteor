import re
from pathlib import Path

# Read the README
readme = Path('README.md').read_text(encoding='utf-8')

# Find the Behaviors sublist.
# This regex captures all lines that start with spaces and then "- [x] " or "- [ ] "
# after the line that contains exactly "- [ ] Behaviors".
behaviors_section = re.search(
    r'- \[ \] Behaviors\n((?:\s+- \[[ x]\] .+\n?)+)',
    readme
)

if not behaviors_section:
    raise SystemExit("Could not find the Behaviors checklist in README.md")

items = behaviors_section.group(1)
completed = len(re.findall(r'^\s+- \[x\]', items, re.MULTILINE))
total = len(re.findall(r'^\s+- \[[ x]\]', items, re.MULTILINE))
percent = int(completed / total * 100) if total else 0

# Create a pure SVG pie chart (no external calls)
svg = f'''<svg width="200" height="200" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
  <!-- Background circle (grey) -->
  <circle cx="100" cy="100" r="90" fill="#E0E0E0" />
  <!-- Progress arc (green) -->
  <circle cx="100" cy="100" r="90" fill="none" stroke="#4CAF50" stroke-width="20"
          stroke-dasharray="{percent * 5.654866} 565.4866"
          stroke-dashoffset="0" stroke-linecap="butt"
          transform="rotate(-90 100 100)" />
  <!-- Percentage text in the center -->
  <text x="100" y="110" text-anchor="middle" font-family="Arial, sans-serif"
        font-size="32" font-weight="bold" fill="#333">{percent}%</text>
</svg>'''

# Write the SVG to docs/progress.svg
Path('docs/progress.svg').write_text(svg, encoding='utf-8')
print(f"Generated progress chart: {completed}/{total} ({percent}%)")