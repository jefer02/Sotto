// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Sotto';

  @override
  String get statusOrganizing => 'Organizando…';

  @override
  String statusRehearsedTimes(int count) {
    return 'Ensayado ×$count';
  }

  @override
  String get statusRehearsed => 'Ensayado';

  @override
  String get statusStructured => 'Estructurado';

  @override
  String get statusDraft => 'Borrador';

  @override
  String get timeJustNow => 'Justo ahora';

  @override
  String timeMinutesAgo(int minutes) {
    return 'hace $minutes min';
  }

  @override
  String timeHoursAgo(int hours) {
    return 'hace $hours h';
  }

  @override
  String timeEditedMinutesAgo(int minutes) {
    return 'Editado hace $minutes min';
  }

  @override
  String timeEditedHoursAgo(int hours) {
    return 'Editado hace $hours h';
  }

  @override
  String get timeYesterday => 'Ayer';

  @override
  String get timeToday => 'Hoy';

  @override
  String get actionGoLive => 'Salir en vivo o terminar la sesión';

  @override
  String get actionGoLiveSub => 'Empieza en la sección elegida en la verificación previa';

  @override
  String get actionPause => 'Pausar o reanudar el seguimiento';

  @override
  String get actionPauseSub => 'Congela el guion; conservas tu lugar';

  @override
  String get actionNextBeat => 'Siguiente frase';

  @override
  String get actionNextBeatSub => 'Avanza una frase — funciona mientras sigue tu voz';

  @override
  String get actionPrevBeat => 'Frase anterior';

  @override
  String get actionPrevBeatSub => 'También pausa el seguimiento 3 segundos';

  @override
  String get actionNextSection => 'Siguiente sección';

  @override
  String get actionPrevSection => 'Sección anterior';

  @override
  String get actionAsk => 'Escuchar una pregunta';

  @override
  String get actionAskSub => 'Escucha a la sala hasta que haya silencio';

  @override
  String get actionSend => 'Enviar la respuesta al chat';

  @override
  String get actionSendSub => 'Mantén medio segundo para que no se active por accidente';

  @override
  String get actionReadAloud => 'Leer la respuesta en voz alta';

  @override
  String get actionReadAloudSub => 'Solo suena en tus auriculares';

  @override
  String get actionDismiss => 'Descartar la respuesta';

  @override
  String get actionDismissSub => 'Vuelve al guion donde lo dejaste';

  @override
  String get actionHistory => 'Historial de preguntas';

  @override
  String get actionHide => 'Ocultar la superposición al instante';

  @override
  String get actionHideSub => 'Sin animación. Pulsa otra vez para mostrarla.';

  @override
  String get actionClickThrough => 'Clic a través';

  @override
  String get actionClickThroughSub => 'La superposición deja de capturar el ratón';

  @override
  String get actionTextBigger => 'Texto más grande';

  @override
  String get actionTextSmaller => 'Texto más pequeño';

  @override
  String get actionMoveDisplay => 'Mover a la siguiente pantalla';

  @override
  String get actionMoveDisplaySub => 'Recuerda una posición por pantalla';

  @override
  String get keySpace => 'Espacio';

  @override
  String get modShiftShort => 'Mayús';

  @override
  String get modShift => 'Mayúsculas';

  @override
  String get modOption => 'Opción';

  @override
  String get modCommand => 'Comando';

  @override
  String get untitledScript => 'Guion sin título';

  @override
  String get sectionOpening => 'Apertura';

  @override
  String get sectionFallback => 'Sección';

  @override
  String get newSectionTitle => 'Nueva sección';

  @override
  String get cueSlide => 'DIAPOSITIVA';

  @override
  String get cuePause => 'PAUSA';

  @override
  String get cueDemo => 'DEMO';

  @override
  String get cueNote => 'NOTA';

  @override
  String copyTitle(String title) {
    return '$title (copia)';
  }

  @override
  String get importUnsupported => 'Sotto puede importar archivos .docx, .pdf, .md y .txt.';

  @override
  String importNoText(String name) {
    return '$name no tiene texto que Sotto pueda leer.';
  }

  @override
  String get importNoBody => 'Este archivo .docx no tiene contenido.';

  @override
  String get pastedScript => 'Guion pegado';

  @override
  String get pastedText => 'Texto pegado';

  @override
  String get dialogImportScript => 'Importar un guion';

  @override
  String get llmRejected => 'La solicitud fue rechazada';

  @override
  String llmBadKey(String provider) {
    return '$provider rechazó la clave de API. Revísala en Ajustes → Integraciones.';
  }

  @override
  String get llmNoModel => 'Modelo no encontrado. Revisa el nombre del modelo en Ajustes → Integraciones.';

  @override
  String llmRateLimit(String provider) {
    return '$provider está limitando las solicitudes. Inténtalo de nuevo en un momento.';
  }

  @override
  String llmServerError(String provider, int status) {
    return '$provider tiene problemas en este momento ($status).';
  }

  @override
  String llmFailed(int status) {
    return 'La solicitud falló ($status)';
  }

  @override
  String get llmRefusal => 'El modelo se negó a responder esta pregunta.';

  @override
  String llmTimeout(String provider) {
    return '$provider no respondió a tiempo.';
  }

  @override
  String llmOffline(String provider) {
    return 'Sin conexión con $provider. Las respuestas necesitan internet; el guion sigue tu voz sin conexión.';
  }

  @override
  String llmUnreachable(String provider, String error) {
    return 'No se pudo conectar con $provider: $error';
  }

  @override
  String llmGenericError(String provider) {
    return '$provider devolvió un error.';
  }

  @override
  String get modelStreamingEn => 'Inglés · en tiempo real';

  @override
  String get modelStreamingEnDesc => 'Sigue tu voz palabra por palabra';

  @override
  String get modelStreamingEnLight => 'Inglés · en tiempo real (ligero)';

  @override
  String get modelStreamingEnLightDesc => 'Para equipos antiguos o de bajo consumo';

  @override
  String get modelWhisperBase => 'Whisper base';

  @override
  String get modelWhisperBaseDesc =>
      'Transcribe preguntas en 99 idiomas; también sigue guiones en español y otros idiomas';

  @override
  String get modelWhisperTurbo => 'Whisper large-v3 turbo';

  @override
  String get modelWhisperTurboDesc => 'Las transcripciones más precisas; necesita un equipo rápido';

  @override
  String modelDownloadFailed(int status) {
    return 'La descarga falló ($status).';
  }

  @override
  String get modelIncomplete => 'El archivo del modelo estaba incompleto.';

  @override
  String get modelOffline =>
      'Sin conexión a internet. Los modelos se descargan una vez y luego funcionan sin conexión.';

  @override
  String get engineUnavailable => 'No disponible';

  @override
  String get engineOnDeviceStreaming => 'En el equipo · en tiempo real';

  @override
  String get engineOnDeviceWhisper => 'En el equipo · Whisper';

  @override
  String get engineModelsMissing =>
      'Los modelos de voz aún no están instalados. Descárgalos en Ajustes → Voz y seguimiento.';

  @override
  String sttEngineFailed(String error) {
    return 'El motor de voz no pudo iniciarse: $error';
  }

  @override
  String get sttNoModel => 'No hay ningún modelo de transcripción instalado.';

  @override
  String get sttStopped => 'El motor de voz se detuvo.';

  @override
  String get micPermission => 'Sotto necesita acceso al micrófono. Permítelo en Ajustes del sistema → Privacidad.';

  @override
  String noticeShortcutsTaken(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count atajos los usan otras apps',
      one: '1 atajo lo usa otra app',
    );
    return '$_temp0';
  }

  @override
  String get noticeNoSpeechForQuestions =>
      'Las preguntas necesitan un motor de voz — ve a Ajustes → Voz y seguimiento.';

  @override
  String get noticeNoQuestion => 'No se entendió la pregunta';

  @override
  String get answerNeedsKey => 'Añade una clave de API en Ajustes → Integraciones para redactar respuestas.';

  @override
  String get noticeCopiedForChat => 'Copiado — pégalo en el chat de la reunión';

  @override
  String get noticeAnswerCopied => 'Respuesta copiada';

  @override
  String get readyNoMic => 'Sin micrófono';

  @override
  String get readyHotkeysOnly => 'Solo atajos';

  @override
  String get readyAdvanceManual => 'Avance: manual';

  @override
  String readyOnDevice(String langs) {
    return 'En el equipo · $langs';
  }

  @override
  String get readyDownloadModels => 'Descarga modelos de voz en Voz y seguimiento';

  @override
  String readyHotkeys(String chord) {
    return 'Atajos $chord';
  }

  @override
  String readyTakenByOther(int count) {
    return '$count en uso por otra app';
  }

  @override
  String get readyNoKey => 'Sin clave de API';

  @override
  String get readyAddKey => 'Añade una en Integraciones para redactar respuestas';

  @override
  String get readyShareWindow => 'Comparte una ventana';

  @override
  String get readyShareWarning => 'Compartir toda la pantalla puede capturar la superposición en macOS 15+';

  @override
  String get sourceQaPrep => 'Preparación de preguntas';

  @override
  String get sourceGeneral => 'Conocimiento general · verificar';

  @override
  String get notInYourNotes => 'No está en tus notas.';

  @override
  String get sidebarShow => 'Mostrar barra lateral';

  @override
  String get sidebarHide => 'Ocultar barra lateral';

  @override
  String get search => 'Buscar';

  @override
  String get navHome => 'Inicio';

  @override
  String get navAllScripts => 'Todos los guiones';

  @override
  String get navSessions => 'Sesiones';

  @override
  String get navArchive => 'Archivo';

  @override
  String get navCollections => 'Colecciones';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get newCollection => 'Nueva colección';

  @override
  String get collectionName => 'Nombre de la colección';

  @override
  String get liveReadiness => 'Listo para salir en vivo';

  @override
  String readinessCount(int passed, int total) {
    return '$passed de $total';
  }

  @override
  String get dropHintDrop => 'Suelta un ';

  @override
  String get dropHintOr => ' o ';

  @override
  String get dropHintPaste => ' en cualquier parte, o pega con  ';

  @override
  String get dropHintOrganize => '  — Sotto lo organiza en secciones, frases e indicaciones.';

  @override
  String get browseFiles => 'Explorar archivos';

  @override
  String get import => 'Importar';

  @override
  String get newScript => 'Nuevo guion';

  @override
  String get upNext => 'A continuación';

  @override
  String get recentScripts => 'Guiones recientes';

  @override
  String get filterAll => 'Todos';

  @override
  String get filterDrafts => 'Borradores';

  @override
  String get filterReady => 'Listos';

  @override
  String get gridView => 'Vista de cuadrícula';

  @override
  String get listView => 'Vista de lista';

  @override
  String get emptyNoScriptsHere => 'Aún no hay guiones aquí';

  @override
  String get emptyWriteOrDrop => 'Escribe uno, pega uno o suelta un archivo en cualquier parte de esta ventana.';

  @override
  String inMinutes(int minutes) {
    return 'en $minutes min';
  }

  @override
  String inHours(int hours) {
    return 'en $hours h';
  }

  @override
  String sectionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count secciones', one: '1 sección');
    return '$_temp0';
  }

  @override
  String atYourPace(String duration, int wpm) {
    return '$duration a tu ritmo ($wpm ppm)';
  }

  @override
  String rehearsedTimes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ensayado $count veces',
      two: 'ensayado dos veces',
      one: 'ensayado una vez',
    );
    return '$_temp0';
  }

  @override
  String prepDocsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documentos de preparación',
      one: '1 documento de preparación',
    );
    return '$_temp0';
  }

  @override
  String get goLive => 'Salir en vivo';

  @override
  String get rehearse => 'Ensayar';

  @override
  String get notRehearsedYet => 'Aún sin ensayar';

  @override
  String lastRehearsal(String duration) {
    return 'Último ensayo $duration';
  }

  @override
  String get deleteCollection => 'Eliminar colección';

  @override
  String get emptyNothingArchived => 'Nada archivado';

  @override
  String get emptyNoScripts => 'Aún no hay guiones';

  @override
  String get emptyNoMatches => 'Sin resultados';

  @override
  String get emptyArchivedHint => 'Los guiones archivados se pueden buscar aquí y nunca aparecen en «A continuación».';

  @override
  String emptyNoMatchesHint(String query) {
    return 'Nada en los títulos ni en el texto coincide con «$query».';
  }

  @override
  String scriptsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count guiones', one: '1 guion');
    return '$_temp0';
  }

  @override
  String get noCollection => 'Sin colección';

  @override
  String importedFinding(String source) {
    return 'Importado de $source. Buscando secciones, frases e indicaciones…';
  }

  @override
  String get importedFromText => 'texto';

  @override
  String get emptyScript => 'Guion vacío';

  @override
  String get menuOpen => 'Abrir';

  @override
  String get menuDuplicate => 'Duplicar';

  @override
  String get menuMoveToCollection => 'Mover a colección';

  @override
  String get menuSchedule => 'Programar…';

  @override
  String get menuExportMarkdown => 'Exportar como Markdown';

  @override
  String get menuArchive => 'Archivar';

  @override
  String get menuUnarchive => 'Desarchivar';

  @override
  String get delete => 'Eliminar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get exportScript => 'Exportar guion';

  @override
  String deleteScriptTitle(String title) {
    return '¿Eliminar «$title»?';
  }

  @override
  String get deleteScriptBody => 'También se elimina su historial de preguntas. No se puede deshacer.';

  @override
  String get emptyNoSessions => 'Aún no hay sesiones';

  @override
  String get emptyNoSessionsHint =>
      'Cada sesión en vivo y cada ensayo quedan aquí con sus tiempos, para que tu ritmo sea cada vez más preciso.';

  @override
  String get rehearsal => 'Ensayo';

  @override
  String get liveSession => 'Sesión en vivo';

  @override
  String get liveChip => 'En vivo';

  @override
  String wpmValue(int wpm) {
    return '$wpm ppm';
  }

  @override
  String questionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count preguntas', one: '1 pregunta');
    return '$_temp0';
  }

  @override
  String get deleteSession => 'Eliminar sesión';

  @override
  String get overlayPreview => 'Vista previa de la superposición';

  @override
  String get followCursor => 'Seguir el cursor';

  @override
  String get layoutTicker => 'Cinta';

  @override
  String get layoutStandard => 'Estándar';

  @override
  String get layoutColumn => 'Columna';

  @override
  String get layoutRail => 'Riel';

  @override
  String get layoutAuto => 'Auto';

  @override
  String beatPosition(int section, int beat, String duration) {
    return 'Frase $section.$beat · $duration';
  }

  @override
  String get noMoreCues => 'No hay más indicaciones';

  @override
  String nextCueIn(int count, String cue) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Siguiente indicación: $cue en $count frases',
      one: 'Siguiente indicación: $cue en 1 frase',
    );
    return '$_temp0';
  }

  @override
  String get listenForWords => 'Palabras a reconocer';

  @override
  String get add => 'Añadir';

  @override
  String get hintWordsExplain => 'Los nombres y cifras de este guion se envían al reconocimiento de voz como pistas.';

  @override
  String get remove => 'Quitar';

  @override
  String get hintWordPlaceholder => 'Un nombre o cifra, luego Intro';

  @override
  String get deliveryCheck => 'Revisión de la presentación';

  @override
  String get markAsReady => 'Marcar como listo';

  @override
  String get checkCuesOrdered => 'Las indicaciones están en orden de lectura';

  @override
  String get checkCuesBackwards => 'Las indicaciones de diapositiva retroceden';

  @override
  String get checkBeatsFit => 'Cada frase cabe en una respiración';

  @override
  String checkLongBeats(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frases largas — más de 28 palabras',
      one: '1 frase larga — más de 28 palabras',
    );
    return '$_temp0';
  }

  @override
  String get checkNumbersSpoken => 'Las cifras están escritas como las dices';

  @override
  String checkNumbersAbbreviated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frases con cifras abreviadas (escribe «48,2 millones», no «48,2M»)',
      one: '1 frase con cifras abreviadas (escribe «48,2 millones», no «48,2M»)',
    );
    return '$_temp0';
  }

  @override
  String checkEmptyBeats(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frases vacías',
      one: '1 frase vacía',
    );
    return '$_temp0';
  }

  @override
  String get scriptMissing => 'Este guion ya no existe.';

  @override
  String get backToLibrary => 'Volver a la biblioteca';

  @override
  String get library => 'Biblioteca';

  @override
  String get saved => 'Guardado';

  @override
  String get editing => 'Editando…';

  @override
  String get tabWrite => 'Escribir';

  @override
  String get tabQaPrep => 'Preguntas';

  @override
  String get tabRehearsals => 'Ensayos';

  @override
  String get structure => 'Estructura';

  @override
  String get organizeAgain => 'Organizar de nuevo — secciones, frases e indicaciones';

  @override
  String get addSection => 'Añadir sección';

  @override
  String get timing => 'Tiempos';

  @override
  String plannedDuration(String duration) {
    return '$duration previstos';
  }

  @override
  String get setTarget => 'fijar objetivo';

  @override
  String targetDuration(String duration) {
    return '$duration objetivo';
  }

  @override
  String paceNote(int wpm) {
    return 'A $wpm ppm.';
  }

  @override
  String paceNoteMeasured(int count, int wpm) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'A $wpm ppm, medido en $count ensayos.',
      one: 'A $wpm ppm, medido en 1 ensayo.',
    );
    return '$_temp0';
  }

  @override
  String get targetLength => 'Duración objetivo';

  @override
  String get durationPlaceholder => 'm:ss — vacío para borrar';

  @override
  String get save => 'Guardar';

  @override
  String get deleteSection => 'Eliminar sección';

  @override
  String timeForSection(String title) {
    return 'Tiempo para «$title»';
  }

  @override
  String wordsAtPace(int words, String duration, int wpm) {
    return '$words palabras · $duration a $wpm ppm';
  }

  @override
  String beatWords(int section, int beat, int words) {
    return 'Frase $section.$beat · $words palabras';
  }

  @override
  String sectionHeader(int index, int count, String duration, String start) {
    return 'Sección $index de $count · $duration · empieza en $start';
  }

  @override
  String get sectionTitle => 'Título de la sección';

  @override
  String get addBeat => '+  Añadir una frase';

  @override
  String get transitionTo => '→  Transición a  ';

  @override
  String get beatHint => 'Una respiración de texto. Escribe [DIAPOSITIVA 3] o [PAUSA] para una indicación.';

  @override
  String get cueMenuSlide => 'Diapositiva';

  @override
  String get cueMenuSlideNext => 'Número de diapositiva +1';

  @override
  String get cueMenuSlidePrev => 'Número de diapositiva −1';

  @override
  String get cueMenuPause => 'Pausa';

  @override
  String get cueMenuDemo => 'Demo';

  @override
  String get cueMenuRemove => 'Quitar indicación';

  @override
  String get addCue => 'Añadir una indicación';

  @override
  String longBeat(int words) {
    return 'Frase larga · $words palabras. ';
  }

  @override
  String get longBeatPause => 'Considera una pausa para respirar con naturalidad.';

  @override
  String longBeatSplitAfter(String word) {
    return '¿Dividir después de «$word» para respirar con naturalidad?';
  }

  @override
  String get ignore => 'Ignorar';

  @override
  String get split => 'Dividir';

  @override
  String get keyPoints => 'Puntos clave';

  @override
  String get keyPointsNote => 'Se muestran en el diseño en columna y en los ensayos';

  @override
  String get keyPointsHint => 'Uno por línea — lo esencial que esta sección debe transmitir';

  @override
  String get addPrepDocument => 'Añadir un documento de preparación';

  @override
  String pastedNotes(int number) {
    return 'Notas pegadas $number';
  }

  @override
  String get suggestNeedsKey => 'Añade una clave de API en Ajustes → Integraciones para sugerir preguntas.';

  @override
  String get noQuestionsReturned => 'El modelo no devolvió preguntas.';

  @override
  String get likelyQuestions => 'Preguntas probables';

  @override
  String get suggestWithAi => 'Sugerir con IA';

  @override
  String get addQuestion => 'Añadir pregunta';

  @override
  String get likelyQuestionsNote =>
      'Si una pregunta en vivo coincide con una de estas, su respuesta aparece al instante — sin llamar al modelo.';

  @override
  String get noPreparedQuestions => 'Aún no hay preguntas preparadas. Añade las que más temes.';

  @override
  String get prepDocuments => 'Documentos de preparación';

  @override
  String get paste => 'Pegar';

  @override
  String get addFile => 'Añadir archivo';

  @override
  String get prepDocumentsNote =>
      'Las respuestas pueden citarlos. Se quedan en este equipo; solo se envían los fragmentos relevantes para cada pregunta.';

  @override
  String get noPrepDocuments =>
      'Memorandos, contratos, preguntas frecuentes — todo aquello sobre lo que te puedan preguntar.';

  @override
  String get dismiss => 'Descartar';

  @override
  String get questionHint => 'La pregunta, tal como alguien la haría';

  @override
  String get deleteQuestion => 'Eliminar pregunta';

  @override
  String get answerHint => 'Tu respuesta. La primera oración será el titular.';

  @override
  String wordsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count palabras', one: '1 palabra');
    return '$_temp0';
  }

  @override
  String get removeDocument => 'Quitar documento';

  @override
  String get noRehearsalsYet => 'Aún no hay ensayos';

  @override
  String get noRehearsalsHint => 'Ensaya con la superposición real. Sotto cronometra cada sección y aprende tu ritmo.';

  @override
  String get rehearseNow => 'Ensayar ahora';

  @override
  String get latestRehearsal => 'Último ensayo';

  @override
  String get latestSession => 'Última sesión';

  @override
  String ofPlanned(String duration) {
    return ' de $duration previstos';
  }

  @override
  String get allRuns => 'Todas las sesiones';

  @override
  String get questionsAsked => 'Preguntas recibidas';

  @override
  String get pfMicrophone => 'Micrófono';

  @override
  String pfMicReady(String device) {
    return '$device · listo';
  }

  @override
  String get pfNoInput => 'No se encontró ningún dispositivo de entrada';

  @override
  String get pfVoiceFollowing => 'Seguimiento de voz';

  @override
  String pfTunedTo(String engine, int wpm) {
    return '$engine · ajustado a $wpm ppm';
  }

  @override
  String get pfOverlay => 'Superposición';

  @override
  String pfOverlayDetail(String placement, int opacity, String size) {
    return '$placement · $opacity % · texto $size';
  }

  @override
  String get pfScreenSharing => 'Compartir pantalla';

  @override
  String get pfShareProtected =>
      'Sotto se oculta de las capturas cuando el sistema lo permite. En macOS 15 y posteriores, compartir toda la pantalla aún puede capturar la superposición — comparte solo la ventana de las diapositivas.';

  @override
  String get pfShareUnprotected =>
      'La protección contra capturas está desactivada. Comparte solo la ventana de las diapositivas.';

  @override
  String get pfAnswers => 'Respuestas';

  @override
  String get pfGrounded => 'Basadas en este guion';

  @override
  String pfPlusPrepDocs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ' + $count documentos de preparación',
      one: ' + 1 documento de preparación',
    );
    return '$_temp0';
  }

  @override
  String get pfQuestionLanguage => ' · responde en el idioma de la pregunta';

  @override
  String get pfMeetingChat => 'Chat de la reunión';

  @override
  String get pfMeetingChatDetail => 'Mantén pulsado para copiar una respuesta y pégala en Zoom, Teams o Meet';

  @override
  String get pfChoose => 'Elegir';

  @override
  String get pfSetUp => 'Configurar';

  @override
  String get pfAdjust => 'Ajustar';

  @override
  String get pfAddKey => 'Añadir clave';

  @override
  String pfSummary(String duration, String sections) {
    return '$duration · $sections';
  }

  @override
  String pfChecksPassed(int passed, int total) {
    return ' · $passed de $total comprobaciones superadas';
  }

  @override
  String get closeEsc => 'Cerrar  esc';

  @override
  String get startFrom => 'Empezar en';

  @override
  String get goLiveInstead => 'Mejor salir en vivo';

  @override
  String get rehearseInstead => 'Mejor ensayar';

  @override
  String get hintNextBeat => 'siguiente frase';

  @override
  String get hintAsk => 'preguntar';

  @override
  String get hintHide => 'ocultar al instante';

  @override
  String get placeUnderCamera => 'Bajo la cámara';

  @override
  String get placeTopLeft => 'Arriba a la izquierda';

  @override
  String get placeTopRight => 'Arriba a la derecha';

  @override
  String get placeLeftEdge => 'Borde izquierdo';

  @override
  String get placeCentered => 'Centrada';

  @override
  String get placeRightEdge => 'Borde derecho';

  @override
  String get placeBottomLeft => 'Abajo a la izquierda';

  @override
  String get placeBottomCentre => 'Abajo al centro';

  @override
  String get placeBottomRight => 'Abajo a la derecha';

  @override
  String get questions => 'Preguntas';

  @override
  String get close => 'Cerrar';

  @override
  String get historyEmpty => 'Las preguntas que respondas en esta sesión aparecerán aquí.';

  @override
  String get outcomeCopied => 'Copiada para el chat';

  @override
  String get outcomeReadAloud => 'Leída en voz alta';

  @override
  String get outcomeDismissed => 'Descartada';

  @override
  String get outcomeShown => 'Mostrada';

  @override
  String get showAgain => 'Mostrar de nuevo';

  @override
  String get copy => 'Copiar';

  @override
  String get paused => 'En pausa';

  @override
  String get hotkeysOnly => 'Solo atajos';

  @override
  String get followingYourVoice => 'Siguiendo tu voz';

  @override
  String get standby => 'En espera';

  @override
  String get onPace => 'A tiempo';

  @override
  String get ahead => 'Adelantado';

  @override
  String get behind => 'Atrasado';

  @override
  String get holding => 'En espera de tu guion';

  @override
  String get resume => 'Reanudar';

  @override
  String get pause => 'Pausar';

  @override
  String get hideInstantly => 'Ocultar al instante';

  @override
  String get endSession => 'Terminar la sesión';

  @override
  String get listening => 'Escuchando';

  @override
  String get done => 'Listo';

  @override
  String get askAway => 'Adelante — Sotto está escuchando a la sala.';

  @override
  String get transcribingQuestion => 'Transcribiendo la pregunta';

  @override
  String get draftingFrom => 'Redactando a partir de';

  @override
  String get noAnswerDrafted => 'No se redactó ninguna respuesta';

  @override
  String get provNotInNotes => 'No está en tus notas';

  @override
  String get provFromPrep => 'De tu preparación de preguntas';

  @override
  String get provFromScript => 'De tu guion y tus notas de preparación';

  @override
  String get provGeneral => 'Incluye conocimiento general — verifícalo';

  @override
  String get predraftedInstant => 'preparada · al instante';

  @override
  String draftedIn(String seconds) {
    return 'redactada en $seconds s';
  }

  @override
  String get copyForChat => 'Copiar para el chat';

  @override
  String get readAloud => 'Leer en voz alta';

  @override
  String get draftAgain => 'Redactar de nuevo';

  @override
  String get copyAnswer => 'Copiar respuesta';

  @override
  String get upNextOverlay => '→  A continuación · ';

  @override
  String get next => 'Siguiente';

  @override
  String get gettingReady => 'Preparando…';

  @override
  String get choosePlaceholder => 'Elegir…';

  @override
  String get setShortcuts => 'Atajos';

  @override
  String get setAppearance => 'Apariencia';

  @override
  String get setVoice => 'Voz y seguimiento';

  @override
  String get setAnswers => 'Respuestas';

  @override
  String get setGeneral => 'General';

  @override
  String get setIntegrations => 'Integraciones';

  @override
  String get setPrivacy => 'Privacidad y datos';

  @override
  String get settings => 'Ajustes';

  @override
  String get groupLive => 'En vivo';

  @override
  String get groupApp => 'Aplicación';

  @override
  String get versionBuild => 'Sotto 1.0 (compilación 1)';

  @override
  String get searchSettings => 'Buscar en ajustes';

  @override
  String get resetToDefaults => 'Restablecer valores';

  @override
  String get reset => 'Restablecer';

  @override
  String get shortcutsDescription =>
      'Funcionan en todas partes mientras estás en vivo — incluso cuando Zoom o tus diapositivas tienen el foco. Todos los atajos comparten una misma combinación, así que solo aprendes la letra.';

  @override
  String get filterShortcuts => 'Filtrar atajos';

  @override
  String get groupOverlay => 'Superposición';

  @override
  String get chord => 'Combinación';

  @override
  String get sottoChord => 'Combinación de Sotto';

  @override
  String get sottoChordSub => 'Compartida por todos los atajos';

  @override
  String get altGrLayouts => 'Distribuciones con AltGr';

  @override
  String get altGrLayoutsSub =>
      'En distribuciones que escriben caracteres con Ctrl + Alt (español, alemán, polaco…), elige Ctrl + Mayús para que los atajos nunca bloqueen «@» o «€».';

  @override
  String get sysPrevInputSource => 'Seleccionar la fuente de entrada anterior';

  @override
  String get sysMoveSpaces => 'Moverse entre Espacios';

  @override
  String get sysSecurityOptions => 'Opciones de seguridad';

  @override
  String conflictAlreadyUsed(String action) {
    return 'Ya lo usa «$action»';
  }

  @override
  String conflictSystem(String os, String meaning) {
    return 'Lo usa $os: $meaning';
  }

  @override
  String get conflictOtherApp => 'Lo usa otra app';

  @override
  String get pressAKey => 'Pulsa una tecla…';

  @override
  String changeShortcutFor(String action) {
    return 'Cambiar el atajo de $action';
  }

  @override
  String get pressToToggle => 'Pulsar una vez';

  @override
  String get holdToTalk => 'Mantener pulsado';

  @override
  String get hold => 'mantener';

  @override
  String get useAnyway => 'Usar de todos modos';

  @override
  String get chooseAnother => 'Elegir otro';

  @override
  String get appearanceDescription =>
      'Cómo se ve la superposición y dónde vive. Cada cambio se previsualiza en vivo a la derecha.';

  @override
  String get theme => 'Tema';

  @override
  String get app => 'Aplicación';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeAuto => 'Auto';

  @override
  String get overlayThemeSub => 'El oscuro se funde con diapositivas y video.';

  @override
  String get matchApp => 'Como la app';

  @override
  String get readability => 'Legibilidad';

  @override
  String get textSize => 'Tamaño del texto';

  @override
  String get linesShown => 'Líneas visibles';

  @override
  String get linesShownSub => 'Antes y después de la línea que estás diciendo';

  @override
  String get opacity => 'Opacidad';

  @override
  String get opacitySub => 'Por debajo del 70 %, aparece un fondo detrás de la línea actual.';

  @override
  String get placement => 'Ubicación';

  @override
  String get position => 'Posición';

  @override
  String get positionSub => 'Mantén la mirada cerca de la cámara';

  @override
  String get layout => 'Diseño';

  @override
  String get layoutSub => 'Se elige automáticamente según el tamaño de la ventana';

  @override
  String get rememberPosition => 'Recordar la posición por pantalla';

  @override
  String get preview => 'Vista previa';

  @override
  String get bgDarkSlide => 'Diapositiva oscura';

  @override
  String get bgLightSlide => 'Diapositiva clara';

  @override
  String get bgVideoCall => 'Videollamada';

  @override
  String get writeToPreview => 'Escribe un guion para previsualizarlo aquí.';

  @override
  String get metricCurrentLine => 'Línea actual, peor caso';

  @override
  String get metricNextLine => 'Siguiente línea, peor caso';

  @override
  String get metricLineLength => 'Longitud de línea a este tamaño';

  @override
  String get motion => 'Movimiento';

  @override
  String get scrolling => 'Desplazamiento';

  @override
  String get scrollingSub => 'Suave se desliza entre frases; Por pasos salta.';

  @override
  String get scrollGlide => 'Suave';

  @override
  String get scrollStep => 'Por pasos';

  @override
  String get reduceMotion => 'Reducir movimiento';

  @override
  String get reduceMotionSub => 'También sigue el ajuste del sistema';

  @override
  String get blurBehind => 'Desenfocar detrás de la superposición';

  @override
  String get blurBehindSub =>
      'Suaviza diapositivas recargadas. Usa el efecto de transparencia del sistema en macOS y el acrílico en Windows 11.';

  @override
  String get voiceDescription =>
      'Cómo te escucha Sotto mientras presentas. El reconocimiento en el equipo mantiene tu voz en este ordenador.';

  @override
  String get stopTest => 'Detener prueba';

  @override
  String get testWithScript => 'Probar con este guion';

  @override
  String get noMicrophoneFound => 'No se encontró ningún micrófono';

  @override
  String get inputLevel => 'Nivel de entrada';

  @override
  String get inputLevelSub => 'Habla con normalidad — apunta a la zona verde';

  @override
  String get noiseSuppression => 'Supresión de ruido';

  @override
  String get noiseSuppressionSub => 'Filtra ventiladores, teclados y el eco de los altavoces';

  @override
  String get questionsComeFrom => 'Las preguntas llegan de';

  @override
  String get questionsComeFromSub =>
      'En una videollamada, elige un dispositivo de bucle (BlackHole, Mezcla estéreo) para capturar el audio de la reunión';

  @override
  String get sameAsMicrophone => 'El mismo que el micrófono';

  @override
  String get recognition => 'Reconocimiento';

  @override
  String get language => 'Idioma';

  @override
  String get alsoRecognize => 'Reconocer también';

  @override
  String get alsoRecognizeSub => 'Para quienes cambian de idioma a mitad de la charla';

  @override
  String get addLanguage => 'Añadir un idioma';

  @override
  String get engine => 'Motor';

  @override
  String get engineOnDeviceSub => 'sherpa-onnx en este equipo · el audio no sale de él';

  @override
  String get following => 'Seguimiento';

  @override
  String get advance => 'Avance';

  @override
  String get followMyVoice => 'Seguir mi voz';

  @override
  String get timed => 'Por tiempo';

  @override
  String get manual => 'Manual';

  @override
  String get moveOnWhenSaid => 'Avanzar cuando haya dicho';

  @override
  String get moveOnWhenSaidSub => 'Más bajo se siente más rápido; más alto nunca avanza antes de tiempo';

  @override
  String get sensitivity => 'Sensibilidad';

  @override
  String get sensitivitySub => 'Alta sigue las paráfrasis, pero puede saltar con improvisaciones';

  @override
  String get low => 'Baja';

  @override
  String get medium => 'Media';

  @override
  String get high => 'Alta';

  @override
  String get holdStill => 'Esperar mientras improviso';

  @override
  String get holdStillSub => 'Espera a que vuelvas al guion';

  @override
  String get allowJumps => 'Permitir saltos entre secciones';

  @override
  String get allowJumpsSub => 'Si te adelantas, la superposición te sigue';

  @override
  String get ready => 'Listo';

  @override
  String get needsSetup => 'Requiere configuración';

  @override
  String get onDeviceModels => 'Modelos en el equipo';

  @override
  String get onDeviceModelsFooter =>
      'Se descargan una vez del proyecto sherpa-onnx y luego funcionan sin conexión. El inglés se sigue en vivo con un modelo en tiempo real; Whisper transcribe preguntas y sigue otros idiomas, incluido el español.';

  @override
  String get installed => 'Instalado';

  @override
  String get removeModel => 'Quitar modelo';

  @override
  String get unpacking => 'Descomprimiendo';

  @override
  String get retry => 'Reintentar';

  @override
  String get download => 'Descargar';

  @override
  String get noSpeechEngine => 'No hay ningún motor de voz disponible.';

  @override
  String get liveCheck => 'Prueba en vivo';

  @override
  String get whatSottoHears => 'Lo que Sotto escucha';

  @override
  String get listeningLower => 'escuchando';

  @override
  String listeningLag(int ms) {
    return 'escuchando · $ms ms desde la última palabra';
  }

  @override
  String get idle => 'inactivo';

  @override
  String get checkWriteFirst => 'Escribe primero un guion — la prueba sigue tus propias palabras.';

  @override
  String checkPressTest(String title) {
    return 'Pulsa «Probar con este guion» y lee «$title» en voz alta.';
  }

  @override
  String get heard => 'Escuchado';

  @override
  String get positionConfidence => 'Confianza de posición';

  @override
  String get beatProgress => 'Progreso de la frase';

  @override
  String get holdingWaiting => 'En espera — esperando a que vuelvas al guion';

  @override
  String get yourPace => 'Tu ritmo';

  @override
  String get wpm => 'ppm';

  @override
  String get paceDefault => 'predeterminado · ensaya para calibrar';

  @override
  String paceFromRehearsals(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'de $count ensayos', one: 'de 1 ensayo');
    return '$_temp0';
  }

  @override
  String get recalibrate => 'Recalibrar';

  @override
  String get slower => 'Más lento';

  @override
  String get faster => 'Más rápido';

  @override
  String get answersDescription =>
      'Cómo se redactan, fundamentan y entregan las respuestas en vivo. Sotto redacta; tú decides qué escucha la sala.';

  @override
  String get grounding => 'Fundamento';

  @override
  String get groundingScriptOnly => 'Solo mi guion y mis documentos de preparación';

  @override
  String get groundingScriptOnlySub => 'Lo más seguro. Dice «No está en tus notas» cuando no puede responder.';

  @override
  String get groundingScriptFirst => 'Primero el guion, conocimiento general si hace falta';

  @override
  String get groundingScriptFirstSub => 'Todo lo que no esté en tu material se marca como «verificar».';

  @override
  String get showSources => 'Mostrar las fuentes bajo cada respuesta';

  @override
  String get style => 'Estilo';

  @override
  String get length => 'Extensión';

  @override
  String get lengthSub => 'Los puntos clave se dicen más rápido que los párrafos';

  @override
  String get headline => 'Titular';

  @override
  String get headlinePlus3 => 'Titular + 3';

  @override
  String get detailed => 'Detallada';

  @override
  String get sameAsQuestion => 'El de la pregunta';

  @override
  String get sameAsScript => 'El del guion';

  @override
  String get tone => 'Tono';

  @override
  String get matchScript => 'Como el guion';

  @override
  String get conversational => 'Conversacional';

  @override
  String get formal => 'Formal';

  @override
  String get listeningForQuestions => 'Escucha de preguntas';

  @override
  String get capture => 'Captura';

  @override
  String get captureSub => 'Solo cuando lo pides — nunca en segundo plano';

  @override
  String get stopAfterSilence => 'Detener tras un silencio de';

  @override
  String get predraft => 'Preparar preguntas probables';

  @override
  String get predraftSub => 'De la preparación de preguntas — las respuestas coincidentes aparecen al instante';

  @override
  String get delivery => 'Entrega';

  @override
  String get voice => 'Voz';

  @override
  String get systemDefault => 'Predeterminada del sistema';

  @override
  String get copyForChatAsks => 'Copiar para el chat requiere';

  @override
  String holdKeyHalfSecond(String keys) {
    return 'Mantener $keys (0,5 s)';
  }

  @override
  String get copyThenPaste => 'Copiar y pegar';

  @override
  String get copyThenPasteSub =>
      'Mantener la tecla de envío copia la respuesta al portapapeles como texto plano. Pégala en el chat de Zoom, Teams o Meet con una pulsación. Nada se publica en tu nombre.';

  @override
  String get whatLeaves => 'Qué sale de este equipo';

  @override
  String get leavesAudio => 'Audio — el tuyo y el de la sala se transcriben en este equipo.';

  @override
  String get leavesQuestion => 'El texto de la pregunta y los fragmentos usados para responderla.';

  @override
  String get leavesNothingElse => 'Nada más: ni guion, ni historial, ni cuenta.';

  @override
  String get generalDescription =>
      'Idioma, ritmo, almacenamiento y valores predeterminados. Todo lo que guarda Sotto vive en este equipo.';

  @override
  String get interface => 'Interfaz';

  @override
  String get interfaceLanguage => 'Idioma';

  @override
  String get interfaceLanguageSub => 'Sistema sigue el idioma de tu equipo';

  @override
  String get langSystem => 'Sistema';

  @override
  String get pace => 'Ritmo';

  @override
  String get wordsPerMinute => 'Palabras por minuto';

  @override
  String get wordsPerMinuteSub => 'Se usa para los tiempos hasta que los ensayos lo calibren';

  @override
  String get storage => 'Almacenamiento';

  @override
  String get dataFolder => 'Carpeta de datos';

  @override
  String get copyPath => 'Copiar ruta';

  @override
  String get format => 'Formato';

  @override
  String get formatSub =>
      'Guiones, ajustes, sesiones e historial de preguntas se guardan en una base de datos local. Las claves de API se guardan en el llavero del sistema.';

  @override
  String get resetAllSettings => 'Restablecer todos los ajustes';

  @override
  String get resetAllSettingsSub => 'Se conservan los guiones, las sesiones y las claves de API';

  @override
  String get aboutSotto => 'Acerca de Sotto';

  @override
  String get aboutSottoBody =>
      'De sotto voce — a media voz. Un asistente para presentaciones en vivo que mantiene tu guion bajo la cámara, sigue tu voz línea a línea y redacta una respuesta cuando la sala hace una pregunta.';

  @override
  String get versionLine => 'Versión 1.0 · compilación 1';

  @override
  String get typefaces => 'Tipografías: Geist, Geist Mono, Atkinson Hyperlegible Next (SIL OFL)';

  @override
  String get addKeyFirst => 'Añade primero una clave.';

  @override
  String connectedFirstToken(String seconds) {
    return 'Conectado · primer token en $seconds s';
  }

  @override
  String get inKeychain => 'En el llavero';

  @override
  String get integrationsDescription =>
      'Las respuestas las redacta DeepSeek. Añade tu clave de API; se guarda en el llavero del sistema y solo se envía a DeepSeek cuando se hace una pregunta.';

  @override
  String get apiKey => 'Clave de API';

  @override
  String get model => 'Modelo';

  @override
  String get testConnection => 'Probar conexión';

  @override
  String get test => 'Probar';

  @override
  String get privacyDescription =>
      'Privacidad por diseño: el audio de quien presenta se queda en este equipo, el de la sala solo se captura con la combinación y solo se envía texto para responder una pregunta — más una captura cuando preguntas por tu pantalla, si lo activas.';

  @override
  String get hideFromCapture => 'Ocultar la superposición de las capturas de pantalla';

  @override
  String get hideFromCaptureSub =>
      'Usa la protección del sistema cuando existe. En macOS 15+, compartir toda la pantalla aún puede capturarla — mejor comparte una ventana.';

  @override
  String get retention => 'Conservación';

  @override
  String get keepHistoryFor => 'Conservar el historial de preguntas';

  @override
  String daysCount(int count) {
    return '$count días';
  }

  @override
  String get aYear => 'Un año';

  @override
  String get deleteQaHistory => 'Eliminar el historial de preguntas';

  @override
  String get deleteQaHistoryConfirm => '¿Eliminar el historial de preguntas?';

  @override
  String get deleteQaHistoryBody => 'Se eliminan todas las preguntas y respuestas registradas.';

  @override
  String get dangerZone => 'Zona de peligro';

  @override
  String get removeApiKeys => 'Quitar las claves de API';

  @override
  String get removeApiKeysSub => 'Elimina todas las claves que Sotto guardó en el llavero';

  @override
  String get removeApiKeysConfirm => '¿Quitar las claves de API?';

  @override
  String get removeApiKeysBody => 'Las respuestas dejarán de funcionar hasta que añadas una clave de nuevo.';

  @override
  String get deleteAllData => 'Eliminar todos los datos locales';

  @override
  String get deleteAllDataSub => 'Guiones, colecciones, sesiones e historial de preguntas';

  @override
  String get deleteEverything => 'Eliminar todo';

  @override
  String get deleteAllDataConfirm => '¿Eliminar todos los datos locales?';

  @override
  String get deleteAllDataBody => 'Se eliminarán todos los guiones y sesiones de este equipo. No se puede deshacer.';

  @override
  String get privVoice => 'Voz';

  @override
  String get privVoiceBody => 'El audio de quien presenta nunca sale de este equipo: la voz se procesa en local.';

  @override
  String get privRoom => 'Audio de la sala';

  @override
  String get privRoomBody => 'Solo se captura con la combinación, se muestra en rojo y se transcribe localmente.';

  @override
  String get privAnswers => 'Respuestas';

  @override
  String get privAnswersBody => 'Solo se envían a DeepSeek el texto de la pregunta y los fragmentos usados.';

  @override
  String get privModels => 'Modelos de voz';

  @override
  String get privModelsBody => 'Se descargan una vez del proyecto sherpa-onnx en GitHub.';

  @override
  String get privConsent => 'Consentimiento';

  @override
  String get privConsentBody =>
      'Las leyes sobre grabación varían. Considera avisar a la sala de que la asistencia de preguntas está activa.';

  @override
  String get llmNoBalance => 'Tu saldo de DeepSeek está vacío. Recárgalo en platform.deepseek.com.';

  @override
  String get integrationsDescriptionBuiltIn =>
      'Las respuestas las redacta DeepSeek con la clave integrada en esta copia de Sotto. Puedes reemplazarla con tu propia clave.';

  @override
  String get deepseekFooter => 'Solo se envían la pregunta y los fragmentos usados para responderla.';

  @override
  String get apiKeyOverrideSub => 'Opcional. Déjala vacía para usar la clave integrada.';

  @override
  String get builtInKey => 'Clave integrada';

  @override
  String get modelsLoading => 'Cargando modelos…';

  @override
  String modelsLoadFailed(String error) {
    return 'No se pudo cargar la lista de modelos: $error';
  }

  @override
  String get deepseekPlatform => 'Cuenta, saldo y claves';

  @override
  String get open => 'Abrir';

  @override
  String beatsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count frases', one: '1 frase');
    return '$_temp0';
  }

  @override
  String cuesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count indicaciones',
      one: '1 indicación',
      zero: 'sin indicaciones',
    );
    return '$_temp0';
  }

  @override
  String get readAloudTitle => 'Leer en voz alta';

  @override
  String get readAloudHeadphones => 'Suena por la salida del sistema — usa auriculares para que la sala no lo oiga.';

  @override
  String welcomeStep(int step, int total) {
    return 'BIENVENIDA · $step DE $total';
  }

  @override
  String get welcomeSkip => 'Omitir por ahora';

  @override
  String get welcomeNext => 'Siguiente';

  @override
  String get welcomeBack => 'Atrás';

  @override
  String get welcomeUseExample => 'Empezar con el ejemplo';

  @override
  String get welcomeModelsTitle => 'Descarga los modelos de voz';

  @override
  String get welcomeModelsBody =>
      'Sotto sigue tu voz en este equipo. Estos modelos se descargan una vez y luego funcionan sin conexión; tu audio nunca sale del dispositivo.';

  @override
  String get welcomeModelsFooter =>
      'Las descargas siguen en segundo plano. Sin modelos, la superposición sigue avanzando con atajos o por tiempo.';

  @override
  String get welcomeScriptTitle => 'Trae tu primer guion';

  @override
  String get welcomeScriptBody =>
      'Sotto lo organiza en secciones, frases de una respiración e indicaciones. También puedes empezar con la charla de ejemplo de tu biblioteca.';

  @override
  String get welcomeImportFile => 'Importar un archivo';

  @override
  String get welcomeImportFileSub => '.docx, .pdf, .md o .txt';

  @override
  String get welcomePaste => 'Pegar texto';

  @override
  String get welcomePasteSub => 'Desde el portapapeles';

  @override
  String get welcomeWrite => 'Escribir desde cero';

  @override
  String get welcomeWriteSub => 'Un guion en blanco';

  @override
  String get overlayStyle => 'Estilo de la superposición';

  @override
  String get overlayStyleTextOnly => 'Solo texto';

  @override
  String get overlayStylePanel => 'Panel';

  @override
  String get overlayStyleTextOnlySub => 'Sin fondo — solo palabras con contorno sobre tus diapositivas';

  @override
  String get overlayStylePanelSub => 'Una tarjeta translúcida detrás del texto';

  @override
  String get overlayStyleTextOnlyFooter =>
      'Los controles y la barra de estado aparecen al pasar el ratón o al usar un atajo, y se desvanecen a los 2 segundos.';

  @override
  String get textColor => 'Color del texto';

  @override
  String get outlineColor => 'Contorno';

  @override
  String get outlineAuto => 'Auto — contrasta con el texto';

  @override
  String get outlineAutoSub => 'Auto: oscuro con texto claro, claro con texto oscuro';

  @override
  String get outlineWidth => 'Grosor del contorno';

  @override
  String get shadowStrength => 'Sombra';

  @override
  String get modelReadsImages => 'lee capturas';

  @override
  String get sourceScreen => 'Tu pantalla';

  @override
  String get actionAskScreen => 'Preguntar sobre la pantalla';

  @override
  String get actionAskScreenSub => 'Toma una captura y luego escucha tu pregunta';

  @override
  String get noticeScreenOff => 'La lectura de pantalla está desactivada — actívala en Ajustes → Privacidad';

  @override
  String get noticeScreenPermission => 'Sotto necesita permiso de Grabación de pantalla — mira Ajustes → Privacidad';

  @override
  String get defaultScreenQuestion => '¿Qué hay en mi pantalla ahora y qué debería decir sobre ello?';

  @override
  String get capturingScreen => 'Capturando pantalla';

  @override
  String get screenshotAttached => 'Captura adjunta — se envía a DeepSeek con tu pregunta';

  @override
  String get screenAwareness => 'Lectura de pantalla';

  @override
  String get screenAwarenessFooter =>
      'Las capturas se toman solo cuando lo pides, se reducen, se envían a DeepSeek con tu pregunta y nunca se guardan. La superposición de Sotto nunca aparece en ellas. Una luz roja «Capturando pantalla» se muestra cada vez.';

  @override
  String get screenAwarenessToggle => 'Dejar que Sotto mire mi pantalla cuando lo pida';

  @override
  String get screenAwarenessToggleSub => 'Desactivado por defecto. Las capturas se envían a DeepSeek.';

  @override
  String get screenTarget => 'Capturar';

  @override
  String get screenTargetOverlay => 'La pantalla de la superposición';

  @override
  String get screenTargetCursor => 'La pantalla bajo el puntero';

  @override
  String get attachSlide => 'Enviar la diapositiva con las preguntas del público';

  @override
  String get attachSlideSub => 'Cada pregunta envía también una captura de lo que hay en pantalla';

  @override
  String get screenPermissionMissing => 'Falta el permiso de Grabación de pantalla';

  @override
  String get screenPermissionMissingSub =>
      'Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla → Sotto';

  @override
  String get openSystemSettings => 'Abrir Ajustes del Sistema';

  @override
  String get privScreen => 'Capturas';

  @override
  String get privScreenOffBody => 'Desactivado. Sotto nunca mira tu pantalla.';

  @override
  String get privScreenOnBody => 'Solo cuando lo pides: una captura va a DeepSeek con la pregunta. Nunca se guarda.';

  @override
  String get readyScreenOk => 'Activada — una captura por cada pregunta sobre la pantalla';

  @override
  String get actionAgentTask => 'Tarea del agente';

  @override
  String get actionAgentTaskSub => 'Di una tarea; el agente la hace en pantalla, paso a paso';

  @override
  String get actionAgentStop => 'Detener el agente';

  @override
  String get actionAgentStopSub => 'Parada de emergencia — cancela al instante y suelta todas las teclas';

  @override
  String get agentOff => 'El modo agente está desactivado — actívalo en Ajustes → Privacidad';

  @override
  String get agentUnsupported => 'Por ahora el modo agente funciona en Windows.';

  @override
  String get agentNeedsAccessibility =>
      'Sotto necesita el permiso de Accesibilidad para controlar el ratón y el teclado — mira Ajustes → Privacidad.';

  @override
  String get agentListening => 'Describe la tarea';

  @override
  String get agentStarting => 'Mirando la pantalla…';

  @override
  String get agentThinking => 'Decidiendo el siguiente paso…';

  @override
  String get agentWaiting => 'Esperándote';

  @override
  String get agentActing => 'Trabajando…';

  @override
  String get agentInControl => 'EL AGENTE TIENE EL CONTROL';

  @override
  String agentStep(int step, int max) {
    return 'paso $step/$max';
  }

  @override
  String get agentStop => 'Detener';

  @override
  String agentStopHint(String keys) {
    return 'Parada de emergencia: $keys — funciona en cualquier sitio';
  }

  @override
  String get agentCouldNotStart => 'No se pudo iniciar';

  @override
  String get agentCompleted => 'Hecho';

  @override
  String get agentStopped => 'Detenido — no se ejecutará nada más';

  @override
  String get agentDeclined => 'Detenido a petición tuya';

  @override
  String agentLimit(int max) {
    return 'Detenido tras $max pasos';
  }

  @override
  String get agentFailed => 'Detenido por un error';

  @override
  String get agentNext => 'SIGUIENTE ACCIÓN';

  @override
  String agentConfirmSensitive(String reason) {
    return 'CONFIRMA — $reason';
  }

  @override
  String get agentRun => 'Ejecutar';

  @override
  String get agentStopTask => 'Detener tarea';

  @override
  String get agentCardTitle => 'Que lo haga el agente';

  @override
  String get agentCardBody =>
      'Describe una tarea — «rellena este formulario con mis datos de los documentos de preparación». El agente trabaja en pantalla, paso a paso, y pregunta antes de enviar, pagar o borrar algo.';

  @override
  String get agentTaskPlaceholder => '¿Qué debe hacer el agente?';

  @override
  String get agentRunTask => 'Empezar';

  @override
  String get agentMode => 'Modo agente';

  @override
  String agentModeFooter(String keys) {
    return 'El agente envía capturas a DeepSeek y mueve el ratón y el teclado, como máximo 25 pasos por tarea. Nunca escribe en campos de contraseña ni maneja datos de pago, siempre pregunta antes de enviar, pagar, borrar o comprar, muestra un marco ámbar mientras tiene el control y registra cada acción en la sesión. $keys lo detiene al instante, desde cualquier sitio.';
  }

  @override
  String get agentToggle => 'Dejar que Sotto controle mi ratón y teclado';

  @override
  String get agentToggleSub => 'Desactivado por defecto. Solo para tareas que tú inicias.';

  @override
  String get agentAutonomy => 'Supervisión';

  @override
  String get agentConfirmEach => 'Confirmar cada acción';

  @override
  String get agentAuto => 'Ejecutar automáticamente';

  @override
  String get agentConfirmEachSub => 'Enter ejecuta la acción mostrada, Esc detiene';

  @override
  String get agentAutoSub => 'Aun así pregunta antes de enviar, pagar, borrar o comprar';

  @override
  String get accessibilityMissing => 'Falta el permiso de Accesibilidad';

  @override
  String get accessibilityMissingSub => 'Ajustes del Sistema → Privacidad y seguridad → Accesibilidad → Sotto';

  @override
  String sessionAgentTask(String task) {
    return 'Agente: $task';
  }

  @override
  String sessionAgentActions(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count acciones', one: '1 acción');
    return '$_temp0';
  }

  @override
  String get readyAgentOk => 'Activado — confirmar cada acción';

  @override
  String get readyAgentAuto => 'Activado — automático, pregunta antes de pasos irreversibles';

  @override
  String agentDoClick(String target, String at) {
    return 'Clic en «$target» en $at';
  }

  @override
  String agentDoDoubleClick(String target, String at) {
    return 'Doble clic en «$target» en $at';
  }

  @override
  String agentDoRightClick(String target, String at) {
    return 'Clic derecho en «$target» en $at';
  }

  @override
  String agentDoMove(String at) {
    return 'Mover el puntero a $at';
  }

  @override
  String agentDoType(String text, String target) {
    return 'Escribir «$text» en $target';
  }

  @override
  String agentDoKeys(String keys) {
    return 'Pulsar $keys';
  }

  @override
  String get agentDoScrollDown => 'Desplazar hacia abajo';

  @override
  String get agentDoScrollUp => 'Desplazar hacia arriba';

  @override
  String agentDoWait(int ms) {
    return 'Esperar $ms ms';
  }

  @override
  String get agentDoScreenshot => 'Volver a mirar la pantalla';

  @override
  String get agentDoDone => 'Terminar';

  @override
  String get agentWhyPassword => 'el campo con el foco es de contraseña';

  @override
  String get agentWhySecret => 'parece un campo de contraseña o código de seguridad';

  @override
  String get agentWhyPayment => 'parece un campo de pago';

  @override
  String get agentWhyCard => 'el texto parece un número de tarjeta';

  @override
  String get agentWhyIrreversible => 'puede enviar, pagar o borrar';

  @override
  String get agentWhySubmitKey => 'puede enviar o borrar';

  @override
  String get agentWhyOutside => 'fuera de la captura';

  @override
  String get privAgent => 'Agente';

  @override
  String get privAgentOffBody => 'Desactivado. Sotto nunca mueve tu ratón ni escribe.';

  @override
  String get privAgentOnBody =>
      'Solo en tareas que inicias: una captura por paso va a DeepSeek; cada acción queda registrada en la sesión.';
}
