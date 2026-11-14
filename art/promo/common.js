// Piezas compartidas del arte promocional (ícono y miniatura). Mismo estilo que el juego:
// tinta, colores de imprenta, hormiga roja chibi, fuente Bangers.
const C = {
  ink: "#141010", paper: "#FFFAEB", yellow: "#FFD23F", red: "#E63946", cyan: "#3EC1F3",
  green: "#6EC85A", crumb: "#DEA65C", dirt: "#96623C", dirtDark: "#70482E", dirtLight: "#D6A874",
  body: "#E83E30", bodyDark: "#CA2C2C", shine: "#FF9C84", cheek: "#FF9696", choc: "#5A3220",
};

function burst(cx, cy, rOut, rIn, n, rot = 0) {
  const pts = [];
  for (let i = 0; i < n * 2; i++) {
    const a = rot + (Math.PI * i) / n;
    const r = i % 2 ? rIn * (0.9 + 0.2 * Math.sin(i * 7.3)) : rOut * (0.88 + 0.12 * Math.cos(i * 3.1));
    pts.push(`${(cx + Math.cos(a) * r).toFixed(1)},${(cy + Math.sin(a) * r).toFixed(1)}`);
  }
  return pts.join(" ");
}

function rays(cx, cy, r, n, color, opacity) {
  let s = "";
  for (let i = 0; i < n; i++) {
    const a0 = (2 * Math.PI * i) / n, a1 = a0 + Math.PI / n;
    s += `<path d="M${cx},${cy} L${cx + Math.cos(a0) * r},${cy + Math.sin(a0) * r} L${cx + Math.cos(a1) * r},${cy + Math.sin(a1) * r}Z" fill="${color}" opacity="${opacity}"/>`;
  }
  return s;
}

const DEFS = `
<pattern id="dots" width="18" height="18" patternUnits="userSpaceOnUse" patternTransform="rotate(20)">
  <circle cx="9" cy="9" r="4" fill="${C.ink}"/>
</pattern>
<pattern id="dotsSmall" width="10" height="10" patternUnits="userSpaceOnUse" patternTransform="rotate(20)">
  <circle cx="5" cy="5" r="2" fill="${C.ink}"/>
</pattern>
<clipPath id="cookieClip"><circle r="95"/></clipPath>
<mask id="cookieBite">
  <rect x="-200" y="-200" width="400" height="400" fill="white"/>
  <circle cx="58" cy="-52" r="30" fill="black"/>
  <circle cx="80" cy="-18" r="24" fill="black"/>
  <circle cx="34" cy="-74" r="20" fill="black"/>
</mask>

<!-- Hormiga chibi de frente, centrada en (0,0), unos 260 de alto -->
<g id="ant">
  <g stroke="${C.ink}" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <path d="M-22,30 L-62,8 L-84,40"/><path d="M22,30 L62,8 L84,40"/>
    <path d="M-20,48 L-60,62 L-74,102"/><path d="M20,48 L60,62 L74,102"/>
    <path d="M-16,58 L-40,92 L-36,130"/><path d="M16,58 L40,92 L36,130"/>
  </g>
  <ellipse cx="0" cy="96" rx="50" ry="40" fill="${C.bodyDark}" stroke="${C.ink}" stroke-width="8"/>
  <ellipse cx="-14" cy="84" rx="16" ry="9" fill="${C.shine}" opacity=".8"/>
  <ellipse cx="0" cy="40" rx="30" ry="28" fill="${C.body}" stroke="${C.ink}" stroke-width="8"/>
  <g stroke="${C.ink}" stroke-width="8" stroke-linecap="round" fill="none">
    <path d="M-26,-92 C-40,-140 -70,-150 -88,-136"/><path d="M26,-92 C40,-140 70,-150 88,-136"/>
  </g>
  <circle cx="-90" cy="-134" r="12" fill="${C.body}" stroke="${C.ink}" stroke-width="7"/>
  <circle cx="90" cy="-134" r="12" fill="${C.body}" stroke="${C.ink}" stroke-width="7"/>
  <ellipse cx="0" cy="-40" rx="72" ry="66" fill="${C.body}" stroke="${C.ink}" stroke-width="9"/>
  <ellipse cx="-34" cy="-80" rx="22" ry="12" fill="${C.shine}" transform="rotate(-25 -34 -80)"/>
  <ellipse cx="-27" cy="-46" rx="19" ry="24" fill="white" stroke="${C.ink}" stroke-width="6"/>
  <ellipse cx="27" cy="-46" rx="19" ry="24" fill="white" stroke="${C.ink}" stroke-width="6"/>
  <ellipse cx="-22" cy="-42" rx="11" ry="14" fill="${C.ink}"/>
  <ellipse cx="32" cy="-42" rx="11" ry="14" fill="${C.ink}"/>
  <circle cx="-18" cy="-48" r="4.5" fill="white"/><circle cx="36" cy="-48" r="4.5" fill="white"/>
  <ellipse cx="-50" cy="-12" rx="13" ry="8" fill="${C.cheek}" opacity=".9"/>
  <ellipse cx="50" cy="-12" rx="13" ry="8" fill="${C.cheek}" opacity=".9"/>
  <path d="M-16,-6 Q0,14 16,-6 Z" fill="${C.ink}" stroke="${C.ink}" stroke-width="5" stroke-linejoin="round"/>
  <path d="M-8,4 Q0,9 8,4" stroke="${C.red}" stroke-width="5" fill="none" stroke-linecap="round"/>
  <path d="M-26,8 Q-34,26 -14,30" stroke="${C.ink}" stroke-width="8" fill="none" stroke-linecap="round"/>
  <path d="M26,8 Q34,26 14,30" stroke="${C.ink}" stroke-width="8" fill="none" stroke-linecap="round"/>
</g>

<!-- Galleta mordida, centrada en (0,0), radio 100 -->
<g id="cookie">
  <g mask="url(#cookieBite)">
    <circle r="100" fill="${C.crumb}" stroke="${C.ink}" stroke-width="10"/>
    <circle r="100" fill="url(#dotsSmall)" opacity=".12"/>
    <circle cx="-30" cy="58" r="72" fill="#C88A44" opacity=".45" clip-path="url(#cookieClip)"/>
    <g fill="${C.choc}" stroke="${C.ink}" stroke-width="5">
      <path d="M-44,-38 l18,-6 l6,16 l-16,8 z"/><path d="M10,-6 l20,2 l-2,18 l-18,-2 z"/>
      <path d="M-56,22 l16,-4 l6,16 l-16,6 z"/><path d="M18,48 l18,-6 l6,16 l-18,6 z"/>
      <path d="M-14,70 l14,-2 l2,14 l-14,2 z"/><path d="M-6,-62 l14,0 l0,12 l-14,0 z"/>
    </g>
  </g>
  <path d="M100,8 A24,24 0 0 0 76,-42 A30,30 0 0 0 54,-74 A20,20 0 0 0 30,-96" fill="none" stroke="${C.ink}" stroke-width="10" stroke-linecap="round"/>
</g>

<g id="crumb"><path d="M-14,-8 L4,-16 L16,-2 L8,14 L-10,12 Z" fill="${C.crumb}" stroke="${C.ink}" stroke-width="5" stroke-linejoin="round"/></g>

<g id="donut">
  <ellipse rx="90" ry="78" fill="#E9A85C" stroke="${C.ink}" stroke-width="10"/>
  <path d="M-80,-10 C-84,-60 -30,-76 0,-74 C40,-76 86,-56 80,-6 C70,10 60,-4 50,14 C38,30 24,8 10,22 C-6,36 -20,10 -36,24 C-52,36 -64,6 -80,-10Z" fill="#FF7BB0" stroke="${C.ink}" stroke-width="8" stroke-linejoin="round"/>
  <ellipse rx="26" ry="20" fill="${C.cyan}" stroke="${C.ink}" stroke-width="8"/>
  <g stroke-width="7" stroke-linecap="round">
    <path d="M-50,-40 l14,-6" stroke="${C.yellow}"/><path d="M30,-50 l10,12" stroke="white"/>
    <path d="M50,-24 l14,4" stroke="${C.cyan}"/><path d="M-30,-58 l6,12" stroke="${C.green}"/>
  </g>
</g>

<g id="strawberry">
  <path d="M0,80 C-60,50 -80,-10 -60,-40 C-40,-62 40,-62 60,-40 C80,-10 60,50 0,80Z" fill="${C.red}" stroke="${C.ink}" stroke-width="9"/>
  <g fill="${C.yellow}"><ellipse cx="-30" cy="-10" rx="5" ry="7"/><ellipse cx="10" cy="-20" rx="5" ry="7"/><ellipse cx="34" cy="4" rx="5" ry="7"/><ellipse cx="-10" cy="20" rx="5" ry="7"/><ellipse cx="14" cy="40" rx="5" ry="7"/><ellipse cx="-34" cy="30" rx="5" ry="7"/></g>
  <path d="M-46,-48 L-20,-44 L-14,-70 L0,-48 L18,-72 L22,-44 L48,-50 L30,-30 L-30,-30 Z" fill="${C.green}" stroke="${C.ink}" stroke-width="7" stroke-linejoin="round"/>
</g>
`;

function titleText(x, y, size, text, rot = -6, fill = C.yellow, shadow = C.red) {
  const st = `font-family:Bangers,Impact,sans-serif;font-size:${size}px;letter-spacing:${size * 0.03}px`;
  const sw = size * 0.12;
  return `<g transform="translate(${x} ${y}) rotate(${rot})" text-anchor="middle">
    <text style="${st}" x="${size * 0.06}" y="${size * 0.07}" fill="${shadow}" stroke="${C.ink}" stroke-width="${sw}" stroke-linejoin="round" paint-order="stroke">${text}</text>
    <text style="${st}" fill="${fill}" stroke="${C.ink}" stroke-width="${sw}" stroke-linejoin="round" paint-order="stroke">${text}</text>
  </g>`;
}
