import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Sotto icon set · 16-point grid, 1.5 px stroke, round caps and joins.
/// Geometry extracted verbatim from the Iconography board. Icons inherit
/// ink; tungsten only when active. Sizes: 14 in buttons, 16 in nav, 20 in
/// empty states.
enum SottoIcons {
  home('<path d="M2.75 6.9 8 2.6l5.25 4.3v6.35H2.75z"></path><path d="M6.4 13.25V9.75h3.2v3.5"></path>'),
  scripts(
    '<rect x="2.75" y="4.25" width="8.5" height="9.5" rx="1.5"></rect><path d="M5.25 1.75h6.5a1.5 1.5 0 0 1 1.5 1.5v7.5"></path><path d="M5.25 7.25h3.5M5.25 10h2.5"></path>',
  ),
  doc(
    '<path d="M3.75 2.25h5.5l3 3v8.5h-8.5z"></path><path d="M9 2.25v3.25h3.25"></path><path d="M6 8.5h4M6 11h2.75"></path>',
  ),
  folder(
    '<path d="M2.25 4.6a1 1 0 0 1 1-1h2.9l1.5 1.5h5.1a1 1 0 0 1 1 1v6.15a1 1 0 0 1-1 1h-9.5a1 1 0 0 1-1-1z"></path>',
  ),
  sessions('<circle cx="8" cy="8" r="5.75"></circle><path d="M8 4.9v3.35l2.1 1.3"></path>'),
  archive(
    '<rect x="2.25" y="2.75" width="11.5" height="3.25" rx="1"></rect><path d="M3.25 6v6.25a1.5 1.5 0 0 0 1.5 1.5h6.5a1.5 1.5 0 0 0 1.5-1.5V6"></path><path d="M6.5 9h3"></path>',
  ),
  search('<circle cx="7.1" cy="7.1" r="4.35"></circle><path d="m10.35 10.35 3.15 3.15"></path>'),
  plus('<path d="M8 3.25v9.5M3.25 8h9.5"></path>'),
  import(
    '<path d="M8 2.25v7.5M5 7l3 3 3-3"></path><path d="M2.75 10.25v2a1.5 1.5 0 0 0 1.5 1.5h7.5a1.5 1.5 0 0 0 1.5-1.5v-2"></path>',
  ),
  structure(
    '<path d="M2.75 3.5h7"></path><path d="M4.4 3.5v8.4a.35.35 0 0 0 .35.35H6.4"></path><path d="M4.4 7.9h2M8.4 7.9h4.85M8.4 12.25h3.35"></path>',
  ),
  play('<path d="M5.25 3.6v8.8a.6.6 0 0 0 .92.5l6.75-4.4a.6.6 0 0 0 0-1L6.17 3.1a.6.6 0 0 0-.92.5z"></path>'),
  pause('<path d="M5.75 3.75v8.5M10.25 3.75v8.5"></path>'),
  up('<path d="M8 12.75v-9.5M4.25 7 8 3.25 11.75 7"></path>'),
  down('<path d="M8 3.25v9.5M4.25 9 8 12.75 11.75 9"></path>'),
  rehearse(
    '<path d="M13.2 8.75A5.25 5.25 0 1 1 11.6 4.3"></path><path d="M13.4 2.6v2.6h-2.6"></path><path d="M6.9 6.15v3.7L9.9 8z"></path>',
  ),
  mic(
    '<rect x="5.75" y="1.75" width="4.5" height="7.75" rx="2.25"></rect><path d="M3.5 7.5a4.5 4.5 0 0 0 9 0"></path><path d="M8 12v2.25"></path>',
  ),
  wave('<path d="M3 6.5v3M5.5 4.75v6.5M8 3v10M10.5 5v6M13 6.75v2.5"></path>'),
  ask(
    '<path d="M2.75 7.4c0-2.8 2.35-4.65 5.25-4.65s5.25 1.85 5.25 4.65S10.9 12.05 8 12.05c-.6 0-1.15-.07-1.7-.2L3.4 13.25l.75-2.35c-.9-.9-1.4-2.1-1.4-3.5z"></path><path d="M6.7 6.05a1.35 1.35 0 1 1 1.9 1.25c-.38.17-.6.47-.6.85v.25"></path><path d="M8 10.05v.01"></path>',
  ),
  history(
    '<path d="M2.9 8.6A5.2 5.2 0 1 0 4.45 4.3"></path><path d="M2.6 2.6v2.6h2.6"></path><path d="M8 5.25V8l1.9 1.2"></path>',
  ),
  send(
    '<path d="M3.25 2.75h9.5a1 1 0 0 1 1 1v6.25a1 1 0 0 1-1 1H7.6l-3.35 2.5v-2.5h-1a1 1 0 0 1-1-1V3.75a1 1 0 0 1 1-1z"></path><path d="M8 8.75v-3.8M6.3 6.6 8 4.9l1.7 1.7"></path>',
  ),
  speaker(
    '<path d="M2.75 6.1v3.8h2.4l3.35 2.85V3.25L5.15 6.1z"></path><path d="M10.9 5.85a3 3 0 0 1 0 4.3"></path><path d="M12.6 4.1a5.5 5.5 0 0 1 0 7.8"></path>',
  ),
  headphones(
    '<path d="M2.75 11.25V8.5a5.25 5.25 0 0 1 10.5 0v2.75"></path><rect x="2.75" y="9.5" width="2.75" height="4" rx="1"></rect><rect x="10.5" y="9.5" width="2.75" height="4" rx="1"></rect>',
  ),
  close('<path d="m4.25 4.25 7.5 7.5M11.75 4.25l-7.5 7.5"></path>'),
  check('<path d="m3.25 8.6 3.1 3 6.4-7.2"></path>'),
  sliders(
    '<path d="M2.75 5h6M12.5 5h.75M2.75 11h.75M7.25 11h6"></path><circle cx="10.75" cy="5" r="1.6"></circle><circle cx="5.25" cy="11" r="1.6"></circle>',
  ),
  keyboard(
    '<rect x="1.75" y="3.75" width="12.5" height="8.5" rx="1.75"></rect><path d="M4.6 6.6h.01M7 6.6h.01M9.4 6.6h.01M11.4 6.6h.01M5.25 9.6h5.5"></path>',
  ),
  onTop(
    '<rect x="5.25" y="2.75" width="8" height="6.5" rx="1.25"></rect><path d="M2.75 6.5v5.75a1 1 0 0 0 1 1h5.75"></path>',
  ),
  cursor('<path d="m3.5 2.9 9 4.5-4.1 1.05L6.9 12.6z"></path><path d="m8.6 8.6 3.2 3.2"></path>'),
  resize('<path d="M9.6 2.75h3.65V6.4M6.4 13.25H2.75V9.6M13.25 2.75 9.2 6.8M2.75 13.25 6.8 9.2"></path>'),
  eye(
    '<path d="M2 8s2.25-4.25 6-4.25S14 8 14 8s-2.25 4.25-6 4.25S2 8 2 8z"></path><circle cx="8" cy="8" r="1.9"></circle>',
  ),
  eyeOff(
    '<path d="M2 8s2.25-4.25 6-4.25S14 8 14 8s-2.25 4.25-6 4.25S2 8 2 8z"></path><circle cx="8" cy="8" r="1.9"></circle><path d="m2.75 13.25 10.5-10.5"></path>',
  ),
  lock(
    '<rect x="3.25" y="7" width="9.5" height="6.75" rx="1.5"></rect><path d="M5.4 7V5.2a2.6 2.6 0 0 1 5.2 0V7"></path>',
  ),
  shield('<path d="M8 1.9 3 3.75v4c0 3.1 2.1 5.3 5 6.35 2.9-1.05 5-3.25 5-6.35v-4z"></path>'),
  plug(
    '<path d="M5.75 2.25v3M10.25 2.25v3"></path><path d="M3.9 5.25h8.2V7.5a4.1 4.1 0 0 1-8.2 0z"></path><path d="M8 11.6v2.15"></path>',
  ),
  link(
    '<path d="M6.9 9.1a2.7 2.7 0 0 0 3.8 0l2-2a2.7 2.7 0 0 0-3.8-3.8l-.6.6"></path><path d="M9.1 6.9a2.7 2.7 0 0 0-3.8 0l-2 2a2.7 2.7 0 0 0 3.8 3.8l.6-.6"></path>',
  ),
  display(
    '<rect x="1.75" y="2.5" width="12.5" height="8.75" rx="1.5"></rect><path d="M8 11.25v2.25M5.5 13.75h5"></path>',
  ),
  camera('<circle cx="8" cy="6.5" r="3.6"></circle><path d="M8 6.5h.01"></path><path d="M8 10.1v2.4M5 13.5h6"></path>'),
  timer('<circle cx="8" cy="9" r="4.9"></circle><path d="M8 6.6V9l1.35.9M6.5 1.9h3M12.1 4.85l.95-.95"></path>'),
  calendar(
    '<rect x="2.25" y="3.25" width="11.5" height="10.5" rx="1.75"></rect><path d="M2.25 6.75h11.5M5.5 1.75v3M10.5 1.75v3"></path>',
  ),
  globe(
    '<circle cx="8" cy="8" r="5.75"></circle><path d="M2.25 8h11.5"></path><path d="M8 2.25c1.6 1.55 2.45 3.5 2.45 5.75S9.6 12.2 8 13.75C6.4 12.2 5.55 10.25 5.55 8S6.4 3.8 8 2.25z"></path>',
  ),
  info('<circle cx="8" cy="8" r="5.75"></circle><path d="M8 7.4v3.6M8 5.1v.01"></path>'),
  alert('<circle cx="8" cy="8" r="5.75"></circle><path d="M8 4.9v3.7M8 11v.01"></path>'),
  copy(
    '<rect x="5.25" y="5.25" width="8.25" height="8.25" rx="1.5"></rect><path d="M10.6 2.5H4.2a1.7 1.7 0 0 0-1.7 1.7v6.4"></path>',
  ),
  refresh('<path d="M13.2 8.75A5.25 5.25 0 1 1 11.6 4.3"></path><path d="M13.4 2.6v2.6h-2.6"></path>'),
  slide(
    '<rect x="1.75" y="2.75" width="12.5" height="8.5" rx="1.25"></rect><path d="m4.75 8.5 2-2 1.6 1.6 2.9-2.9M8 11.25v2.5"></path>',
  ),
  quote(
    '<path d="M3 9.75V8.1c0-2 1-3.35 3-4.1M8.75 9.75V8.1c0-2 1-3.35 3-4.1"></path><path d="M3 9.75h2.75v2.75H3zM8.75 9.75h2.75v2.75H8.75z"></path>',
  ),
  enter('<path d="M12.75 3.5v4.25a1.5 1.5 0 0 1-1.5 1.5H3.5"></path><path d="M6.25 6.5 3.5 9.25 6.25 12"></path>'),
  layers(
    '<path d="M8 2.25 2.25 5.4 8 8.55l5.75-3.15z"></path><path d="m2.25 8.1 5.75 3.15 5.75-3.15"></path><path d="m2.25 10.8 5.75 3.15 5.75-3.15"></path>',
  ),
  moon('<path d="M12.9 9.6A5.1 5.1 0 1 1 6.4 3.1a4.1 4.1 0 0 0 6.5 6.5z"></path>'),
  sun(
    '<circle cx="8" cy="8" r="2.75"></circle><path d="M8 1.75v1.5M8 12.75v1.5M1.75 8h1.5M12.75 8h1.5M3.6 3.6l1.05 1.05M11.35 11.35l1.05 1.05M3.6 12.4l1.05-1.05M11.35 4.65l1.05-1.05"></path>',
  ),
  auto(
    '<circle cx="8" cy="8" r="5.75"></circle><path d="M8 2.25v11.5A5.75 5.75 0 0 0 8 2.25z" fill="currentColor"></path>',
  ),
  form(
    '<rect x="2.75" y="2.75" width="10.5" height="10.5" rx="1.5"></rect><path d="M5 6l1 1 2-2M9.5 6.25h1.5M5 10l1 1 2-2M9.5 10.25h1.5"></path>',
  ),
  chat(
    '<path d="M2.75 4.25a1.5 1.5 0 0 1 1.5-1.5h7.5a1.5 1.5 0 0 1 1.5 1.5v5a1.5 1.5 0 0 1-1.5 1.5H7.25l-3 2.5v-2.5a1.5 1.5 0 0 1-1.5-1.5z"></path>',
  ),
  stop('<rect x="4" y="4" width="8" height="8" rx="1.5"></rect>'),
  grip('<path d="M6 4h.01M10 4h.01M6 8h.01M10 8h.01M6 12h.01M10 12h.01"></path>');

  const SottoIcons(this.body);
  final String body;

  String svg(Color color) {
    final hex = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final opacity = color.a;
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" '
        'fill="none" stroke="$hex" stroke-opacity="$opacity" stroke-width="1.5" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '${body.replaceAll('currentColor', hex)}</svg>';
  }
}

class SottoIcon extends StatelessWidget {
  const SottoIcon(this.icon, {super.key, this.size = 14, this.color});

  final SottoIcons icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFFF2EFE9);
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.string(icon.svg(c), width: size, height: size),
    );
  }
}

/// The cue mark: a tungsten dot beside three bars — the brand glyph.
class CueMark extends StatelessWidget {
  const CueMark({super.key, this.size = 20, this.ink, this.cue, this.hollow = false});

  final double size;
  final Color? ink;
  final Color? cue;

  /// Hollow reads as "Hidden" in the menu bar.
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    final i = ink ?? const Color(0xFFF2EFE9);
    final c = cue ?? const Color(0xFFF4B55C);
    String hex(Color x) => '#${(x.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final dot = hollow
        ? '<circle cx="6" cy="16" r="2.4" fill="none" stroke="${hex(c)}" stroke-width="1.2"/>'
        : '<circle cx="6" cy="16" r="3" fill="${hex(c)}"/>';
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'
        '<rect x="12" y="6" width="10" height="4" rx="2" fill="${hex(i)}" fill-opacity="0.34"/>'
        '$dot'
        '<rect x="12" y="14" width="17" height="4" rx="2" fill="${hex(i)}"/>'
        '<rect x="12" y="22" width="13" height="4" rx="2" fill="${hex(i)}" fill-opacity="0.6"/>'
        '</svg>';
    return SvgPicture.string(svg, width: size, height: size);
  }
}
