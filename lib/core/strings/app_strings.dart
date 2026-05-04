/// Centralized user-facing strings for the EDU AI app.
///
/// Edit this file to change wording across the entire application.
/// Technical strings (API keys, route names, debug logs) are NOT included here.
class AppStrings {
  AppStrings._();

  // ── Navigation ──
  static const navPrehled = 'Prehled';
  static const navChat = 'Chat';
  static const navKurzy = 'Kurzy';
  static const navNovinky = 'Novinky';

  // ── App ──
  static const appTitle = 'Edu';
  static const appName = 'EduAI';

  // ── Welcome / Home ──
  static const welcomeGreeting = 'Ahoj';
  static const welcomeDescription = 'Vítej ve své\nnové appce!';
  static const guideHeading = 'Začněte s návodem';
  static const guideTitle = 'Jak používat EDU AI';
  static const guideSubtitle =
      'Rychlý úvod do aplikace EDU AI. '
      'Kde najdeš AI pomoc, jak fungují lekce '
      'a jak si ukládat věci k opakování.';
  static const guideButton = 'Začít cvičení';
  static const promoBadge = 'KNIHOVNA';
  static const promoTitle = 'Prozkoumej kurzy!';
  static const promoDescription = 'V knihovně najdeš kurzy,\nkteré máš nyní k dispozici';
  static const sectionQuickQuizzes = 'Rychlé kvízy';
  static const sectionContinue = 'Pokračovat';
  static const defaultUserName = 'Uživatel';

  // ── Chat placeholder ──
  static const chatTitle = 'Chat';
  static const chatLockedMessage = 'Chat se vám otevře po získání vyšší úrovně';

  // ── Add placeholder ──
  static const addTitle = 'Připojit / Přidat';
  static const contentComingSoon = 'Tento obsah teprve připravujeme';

  // ── Novinky placeholder ──
  static const novinkyTitle = 'Novinky';

  // ── Kurzy tab ──
  static const kurzyTitle = 'Kurzy';
  static const filterAll = 'Všechny';
  static const filterInProgress = 'Probíhající';
  static const filterNotStarted = 'Nezahájené';
  static const filterCompleted = 'Dokončeno';
  static const kurzyEmptyTitle = 'Zatím nemáš žádné kurzy';
  static const kurzyEmptySubtitle = 'Prozkoumej knihovnu a vyber si kurzy, které tě zajímají';
  static const kurzyExploreLibrary = 'Prozkoumat knihovnu';
  static const defaultCourseName = 'Kurz';

  // ── Auth ──
  static const authHeadline = 'Learn Smarter\nAnywhere';
  static const authCodeLabel = 'Kód kurzu nebo přihlašovací kód';
  static const authVerifyingCode = 'Ověřuji kód...';
  static const authContinue = 'Pokračovat';
  static const authOr = 'or';
  static const authLoginSignUp = 'Log In / Sign Up';
  static const authTerms = 'Terms';
  static const authPrivacy = 'Privacy';
  static const authEmailHint = 'Tvůj e-mail';
  static const authLogin = 'Přihlásit se';
  static const authOrCzech = 'Nebo';
  static const authGoogleLogin = 'Přihlásit pomocí Google';
  static const authMicrosoftLogin = 'Přihlásit pomocí Microsoft';
  static const authAppleLogin = 'Přihlásit pomocí Apple';
  static const authTermsNotice = 'By signing up, you agree to our\n';
  static const authTermsAndPrivacy = 'Terms and Privacy Policy';
  static const authEmptyEmailError = 'Zadej prosím e-mailovou adresu';
  static const authInvalidEmailError = 'Zadej platnou e-mailovou adresu';
  static String codeNotFound(String pin) => 'Kód "$pin" nebyl nalezen';
  static const authUserCreateError = 'Nepodařilo se vytvořit uživatele';
  static const authCourseLoadError = 'Kurz se nepodařilo načíst';
  static const authCourseDownloadError = 'Kurz se nepodařilo stáhnout. Zkontroluj připojení a zkus to znovu.';

  // ── Profile ──
  static const profileTitle = 'Můj účet';
  static const profileSectionAccount = 'Účet';
  static const profileEditProfile = 'Upravit profil';
  static const profilePrivacy = 'Soukromí a zabezpečení';
  static const profileSectionSettings = 'Nastavení';
  static const profileTheme = 'Motiv';
  static const profileNotifications = 'Oznámení';
  static const profileLanguage = 'Jazyk';
  static const profileComingSoon = 'Připravujeme';
  static const profileSectionMore = 'Další';
  static const profileAbout = 'O aplikaci';
  static const profileTerms = 'Podmínky použití';
  static const profileLogout = 'Odhlásit se';
  static const profileLogin = 'Přihlásit se';
  static const profileStatCourses = 'Kurzy';
  static const profileStatStreak = 'Streak';
  static const profileStatAchievements = 'Úspěchy';
  static const profileQuickAchievements = 'Úspěchy';
  static const profileQuickLibrary = 'Knihovna';

  // ── Profile Setup ──
  static const profileSetupTitle = 'Vytvoř svůj profil';
  static const profileSetupNameLabel = 'Jak se jmenuješ?';
  static const profileSetupNameHint = 'Tvoje jméno';
  static const profileSetupAvatarLabel = 'Vyber si avatara';
  static const profileSetupSubjectsLabel = 'Vyber si prostředí';
  static const profileSetupNameError = 'Zadej prosím své jméno';
  static const profileSetupSyncWarning = 'Profil uložen lokálně. Synchronizace proběhne později.';
  static String profileSetupSaveError(String error) => 'Chyba při ukládání: $error';

  // ── Edit Profile ──
  static const editProfileTitle = 'Upravit profil';
  static const editProfileNameLabel = 'Jméno';
  static const editProfileEmailLabel = 'E-mail';
  static const editProfileNameHint = 'Zadejte jméno';
  static const editProfileEmailReadonly = 'E-mail nelze změnit';
  static const editProfileEmptyNameError = 'Jméno nemůže být prázdné';
  static const editProfileSaveError = 'Nepodařilo se uložit změny';
  static const editProfileSaveButton = 'Uložit změny';

  // ── Library (Knihovna) ──
  static const libraryTitle = 'Knihovna';
  static const librarySubtitle = 'Vyber si kurzy a stáhni si je';
  static const libraryCodeTitle = 'Máš kód kurzu?';
  static const libraryCodeShort = 'Zadej 6místný kód';
  static String libraryCodeNotFound(String code) => 'Kurz s kódem "$code" nebyl nalezen';
  static const libraryLoginRequired = 'Pro stažení kurzu se musíš přihlásit';
  static const libraryLoadError = 'Kurz se nepodařilo načíst';
  static const librarySearchingCourse = 'Hledám kurz...';
  static const libraryEmptyTitle = 'Knihovna je prázdná';
  static const libraryEmptySubtitle = 'Zatím tu nejsou žádné kurzy k dispozici';
  static const libraryCoursesLoadError = 'Nepodařilo se načíst kurzy';
  static const libraryCourseAlreadyCompleted = 'Tento kurz byl již dokončen.';
  static String libraryCourseDownloadFailed(String name) =>
      'Kurz "$name" se nepodařilo stáhnout. Zkuste to znovu.';
  static String libraryCourseAdded(String name) => 'Kurz "$name" přidán do tvé knihovny';
  static String libraryCourseDownloadError(String error) => 'Nepodařilo se stáhnout kurz: $error';
  static String libraryCourseUpdated(String name) => 'Kurz "$name" byl aktualizován';
  static String libraryCourseUpdateError(String error) => 'Nepodařilo se aktualizovat kurz: $error';
  static const libraryUpdating = 'Aktualizuji...';
  static const libraryDownloading = 'Stahuji...';
  static const libraryUpdate = 'Aktualizovat';
  static const libraryLaunch = 'Spustit';
  static const libraryDownload = 'Stáhnout';
  static String lessonsCount(int count) => '$count lekcí';
  static String durationHours(int hours) => '$hours hod';
  /// Smart duration: "45 min", "1 hod", "1 hod 20 min"
  static String durationSmart(int totalMinutes) {
    if (totalMinutes < 60) return '$totalMinutes min';
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (mins == 0) return '$hours hod';
    return '$hours hod $mins min';
  }

  // ── Course Detail ──
  static const courseProgress = 'Postup';
  static const courseDescription = 'Popis kurzu';
  static const courseLessons = 'Lekce';
  static const courseShowMore = 'Zobrazit více';
  static const courseShowLess = 'Skrýt';
  static String courseShowMoreCount(int count) => 'Zobrazit další ($count)';
  static const courseQuizzes = 'Kvízy';
  static const courseShowAll = 'Zobrazit vše';
  static const courseContinueLesson = 'Pokračovat v lekci';
  static const courseExercise = 'Cvičení';
  static const courseQuiz = 'Kvíz';
  static const courseCompleted = 'DOKONČENO';
  static const courseCurrent = 'AKTUÁLNÍ';
  static String courseQuestionsCount(int count) => '$count otázek';
  static const courseCorruptedTitle = 'Kurz se nepodařilo načíst';
  static const courseCorruptedMessage = 'Data kurzu jsou neúplná nebo poškozená. Zkuste kurz stáhnout znovu v knihovně.';
  static const courseBack = 'Zpět';
  static const courseStartQuiz = 'Začít kvíz';
  static const courseContinueQuiz = 'Pokračovat v kvízu';
  static const courseQuizUnlockHint = 'Odpověz na otázky a odemkni lekce';
  static const courseNoBookmarks = 'Zatím nemáš žádné uložené bloky k procvičování.\nPřidej je pomocí záložky v lekcích.';
  static const courseNoQuestions = 'V tomto kurzu nejsou žádné otázky.';
  static const courseUpdateAvailable = 'K dispozici je nová verze kurzu';
  static const courseUpdateRequired = 'Aktualizujte kurz pro pokračování';
  static const courseCardUpdate = 'Aktualizace';

  // ── Lesson Detail ──
  static String lessonTitle(int index, String title) => 'Lekce $index: $title';
  static const lessonEmptyTitle = 'Obsah lekce se připravuje';
  static const lessonEmptyMessage = 'Tato lekce zatím nemá žádný obsah.';
  static const lessonFinishCourse = 'Dokončit kurz';
  static const lessonNextLesson = 'Další lekce';
  static const lessonBackToDetail = 'Zpět na detail kurzu';
  static const lessonCourseCompleted = 'Gratulujeme! Dokončil jsi celý kurz.';
  static const lessonSelectAnswerFirst = 'Nejprve vyber odpověď';
  static const lessonExplanation = 'Vysvětlení';
  static String lessonDetailedExplanation(String title) => 'Podrobnější vysvětlení: $title';
  static String lessonExplanationTitle(String title) => 'Vysvětlení: $title';
  static const lessonFeedbackClear = 'Už je to jasné';
  static const lessonFeedbackPractice = 'Přidat k procvičování';
  static const lessonFeedbackPracticeAdded = 'Přidáno k procvičování';
  static const lessonFeedbackConfused = 'Nerozumím tomu';
  static const lessonFeedbackClarify = 'Upřesni svůj dotaz';
  static const lessonFeedbackHint = 'Napiš více o problému...';
  static String lessonFeedbackCharCount(int count) => '$count/500 znaků';
  static const lessonFeedbackThanks = 'Děkujeme za zpětnou vazbu!';
  static const lessonFeedbackSend = 'Odeslat';
  static const lessonVideoError = 'Nepodařilo se načíst video';
  static const lessonWriteAnswer = 'Napiš odpověď...';
  static const lessonCheckAnswer = 'Zkontrolovat';
  static const lessonCorrect = 'Správně!';
  static String lessonCorrectAnswer(String answer) => 'Správná odpověď: $answer';
  static const lessonQuestionLabel = 'Otázka';

  // ── Quiz ──
  static const quizTitle = 'Kvíz';
  static const quizExerciseTitle = 'Cvičení';
  static String quizCardProgress(int current, int total) => 'Karta $current z $total';
  static String quizCorrectCount(int correct, int total) => '$correct/$total správně';
  static const quizCompleted = 'Kvíz dokončen!';
  static const quizReviewCompleted = 'Opakování dokončeno!';
  static String quizCorrectResult(int correct, int total) => '$correct z $total správně';
  static String quizCardsReviewed(int total) => 'Prošel jsi $total karet';
  static const quizAllCorrect = 'Výborně! Všechno správně!';
  static const quizGreatJob = 'Skvělá práce!';
  static const quizTryAgain = 'Zkus to znovu!';
  static const quizGreatReview = 'Skvělé opakování!';
  static const quizDone = 'Hotovo';
  static const quizConfirmSubmit = 'Opravdu chceš kvíz odeslat? Potom se k němu již nejde vrátit.';
  static const quizConfirmBack = 'Zpět';
  static const quizConfirmSend = 'Odeslat';
  static const quizThankYou = 'Skvělé, díky. Teď vím, jaké úlohy ti příště nabídnu.';
  static const quizRetry = 'Zkusit znovu';
  static const quizReview = 'Opakování';
  static const quizFinish = 'Dokončit';
  static const quizNext = 'Další';
  static const quizCheck = 'Zkontrolovat';
  static const quizAnswerHint = 'Zadej odpověď...';
  static String quizCorrectAnswer(String answer) => 'Správná odpověď: $answer';
  static const quizCorrectLabel = 'Správně!';
  static const quizIncorrectLabel = 'Špatně';

  // ── Exercise ──
  static const exerciseSelectCorrect = 'Vyber správnou odpověď';
  static const exerciseSelectAll = 'Vyber všechny správné odpovědi';
  static const exerciseWriteAnswer = 'Napiš svou odpověď';
  static const exerciseAnswerHint = 'Tvoje odpověď...';
  static String exerciseCharCount(int count) => '$count/500 znaků';
  static const exerciseCorrect = 'Správně';
  static const exerciseIncorrect = 'Špatně';
  static String exerciseCorrectAnswer(String answer) => 'Správná odpověď je: $answer';
  static const exerciseExplanationLabel = 'Vysvětlení:';

  // ── Achievements ──
  static const achievementsTitle = 'Úspěchy';
  static String achievementsXpRemaining(int xp, int nextLevel) => 'Zbývá $xp XP do lvl $nextLevel';
  static String achievementsDaysCount(int days) => '$days ${days == 1 ? 'den' : 'dní'}';
  static const achievementsTrophies = 'Trofeje';
  static const achievementsEarnedTrophies = 'Získané trofeje';
  static const achievementsChallenges = 'Výzvy';
  static const achievementsSkills = 'Dovednosti';
  static const achievementsSkillsPlaceholder = 'Těším se, co společně zvládneme.';

  // Skill tab filters
  static const skillTabAll = 'Všechny';
  static const skillTabBeginner = 'Začátečník';
  static const skillTabIntermediate = 'Pokročilý';
  static const skillTabExpert = 'Expert';
  static String skillLevel(double level) =>
      'Úroveň: ${level.toStringAsFixed(1)}';
  static String skillConfidence(int low, int high) =>
      'Interval jistoty: $low–$high';
  static const achievementsGoals = 'Cíle';
  // Mock trophy strings
  static const challengeMasterpiece = 'Mistrovský kousek';
  static const trophyBiologist = 'Mistrovský biolog';
  static const trophyBiologistDesc = 'Získej 90% nebo více v kvízu';
  static const trophyWeekStreak = 'Týdenní série';
  static const trophyWeekStreakDesc = 'Uč se 7 dní v řadě';
  // Mock goal strings
  static const goalCompleteLessons = 'Dokončit 10 lekcí';
  static const goalCompleteLessonsDesc = '+100 XP po dokončení';
  static const goalPerfectScores = 'Získat 5 perfektních skóre';
  static const goalPerfectScoresDesc = '+150 XP po dokončení';
  // Time ago
  static const timeYesterday = 'Včera';
  static String timeDaysAgo(int days) => 'Před $days dny';
  static String timeHoursAgo(int hours) => 'Před $hours hod';
  static String timeMinutesAgo(int minutes) => 'Před $minutes min';
  static const timeJustNow = 'Právě teď';

  // ── Terms ──
  static const termsTitle = 'Podmínky použití';
  static const termsLastUpdated = 'Poslední aktualizace: 19. ledna 2026';
  static const termsSection1Title = '1. Úvodní ustanovení';
  static const termsSection1Body =
      'Tyto podmínky použití upravují práva a povinnosti uživatelů '
      'aplikace EDU-AI. Používáním aplikace souhlasíte s těmito '
      'podmínkami. Aplikace je určena pro vzdělávací účely a je '
      'provozována společností EduAI s.r.o.';
  static const termsSection2Title = '2. Uživatelský účet';
  static const termsSection2Body =
      'Pro využívání plných funkcí aplikace je nutné vytvořit '
      'uživatelský účet. Uživatel je povinen poskytnout pravdivé '
      'údaje a chránit své přihlašovací údaje. Za veškeré aktivity '
      'provedené pod vaším účtem nesete odpovědnost.';
  static const termsSection3Title = '3. Autorská práva';
  static const termsSection3Body =
      'Veškerý obsah v aplikaci, včetně kurzů, textů, grafiky a '
      'softwarového kódu, je chráněn autorským právem. Uživatel '
      'získává pouze licenci k osobnímu nekomerčnímu využití obsahu. '
      'Kopírování, distribuce nebo komerční využití bez písemného '
      'souhlasu je zakázáno.';
  static const termsSection4Title = '4. Pravidla používání';
  static const termsSection4Body =
      'Uživatel se zavazuje používat aplikaci v souladu s právními '
      'předpisy a dobrými mravy. Je zakázáno šířit nevhodný obsah, '
      'pokoušet se o neoprávněný přístup k systémům, nebo jakýmkoli '
      'způsobem narušovat chod aplikace.';
  static const termsSection5Title = '5. Ochrana osobních údajů';
  static const termsSection5Body =
      'Zpracování osobních údajů se řídí Zásadami ochrany osobních '
      'údajů a nařízením GDPR. Shromažďujeme pouze údaje nezbytné '
      'pro poskytování služeb. Vaše údaje nikdy neprodáváme třetím '
      'stranám.';
  static const termsSection6Title = '6. Omezení odpovědnosti';
  static const termsSection6Body =
      'Aplikace je poskytována "tak jak je". Provozovatel nenese '
      'odpovědnost za případné škody vzniklé používáním aplikace, '
      'ztrátu dat nebo přerušení služby. Maximální odpovědnost je '
      'omezena na výši zaplacených poplatků.';
  static const termsSection7Title = '7. Změny podmínek';
  static const termsSection7Body =
      'Vyhrazujeme si právo tyto podmínky kdykoli změnit. O změnách '
      'budete informováni prostřednictvím aplikace nebo e-mailem. '
      'Pokračováním v používání aplikace po změně podmínek '
      'vyjadřujete souhlas s novým zněním.';
  static const termsSection8Title = '8. Kontakt';
  static const termsSection8Body =
      'V případě dotazů nebo připomínek nás můžete kontaktovat na '
      'e-mailové adrese podpora@eduai.cz nebo prostřednictvím '
      'kontaktního formuláře v aplikaci.';

  // ── Privacy ──
  static const privacyTitle = 'Soukromí a zabezpečení';
  static const privacyComingSoon = 'Připravujeme';
  static const privacyComingSoonMessage =
      'Na nastavení soukromí a zabezpečení právě pracujeme. Brzy zde najdete možnosti pro správu vašich dat a bezpečnostní nastavení.';

  // ── Bookmarks List ──
  static const aboutSavedBookmarks = 'Uložené záložky';
  static const bookmarksListTitle = 'Uložené záložky';
  static const bookmarksListEmpty = 'Zatím nemáš žádné uložené záložky.\nPřidej je pomocí záložky v lekcích.';
  static const bookmarksListCourseNotDownloaded = 'Kurz není stažen';

  // ── About / Debug ──
  static const aboutTitle = 'O aplikaci';
  static const aboutSectionAppInfo = 'Informace o aplikaci';
  static const aboutAppName = 'EduAI';
  static const aboutLabelName = 'Název';
  static const aboutLabelVersion = 'Verze';
  static const aboutLabelBuild = 'Build';
  static const aboutBuildValue = 'Release';
  static const aboutLabelFlutter = 'Flutter';
  static const aboutFlutterValue = 'SDK 3.10+';
  static const aboutVersionUnavailable = 'Nedostupná';
  static const aboutSectionStatus = 'Stav systému';
  static const aboutDatabase = 'Databáze';
  static const aboutDatabaseReady = 'Připravena';
  static const aboutDatabaseNotInit = 'Neinicializována';
  static const aboutUserLoggedIn = 'Uživatel přihlášen';
  static const aboutGuestPin = 'Host (PIN)';
  static const aboutYes = 'Ano';
  static const aboutNo = 'Ne';
  static const aboutApiAuth = 'API autorizace';
  static const aboutConnection = 'Připojení';
  static const aboutConnectionChecking = 'Kontrola...';
  static const aboutConnectionError = 'Chyba';
  static const aboutSyncState = 'Sync stav';
  static const aboutSyncReady = 'Připraveno';
  static const aboutSyncSyncing = 'Synchronizace...';
  static const aboutSyncError = 'Chyba';
  static const aboutLastSync = 'Poslední sync';
  static const aboutNextSync = 'Další sync';
  static const aboutSyncNever = 'Zatím neproběhl';
  static const aboutSectionDbStats = 'Statistiky databáze';
  static const aboutCoursesCount = 'Počet kurzů';
  static const aboutPendingSync = 'Čekající sync';
  static const aboutSectionActions = 'Akce';
  static const aboutForceSync = 'Vynutit synchronizaci';
  static const aboutClearSyncQueue = 'Vymazat sync frontu';
  static const aboutRefreshStatus = 'Obnovit stav';
  static const aboutClearAuthToken = 'Vymazat auth token';
  static const aboutClearCourses = 'Vymazat kurzy z knihovny';
  static const aboutFactoryReset = 'Tovární reset (smazat vše)';
  static const aboutSectionApiConfig = 'API konfigurace';
  static const aboutBaseUrl = 'Base URL';
  static const aboutAuth = 'Auth';
  static const aboutAuthValue = 'Laravel Sanctum';
  static const aboutConnWifi = 'WiFi';
  static const aboutConnMobile = 'Mobilní data';
  static const aboutConnEthernet = 'Ethernet';
  static const aboutConnOffline = 'Offline';
  static String aboutSyncQueueCleared(int count) => 'Smazáno $count položek ze sync fronty';
  static const aboutSyncCompleted = 'Synchronizace dokončena';
  static String aboutSyncErrorMsg(String error) => 'Chyba synchronizace: $error';
  static const aboutClearTokenTitle = 'Vymazat token?';
  static const aboutClearTokenMessage = 'Toto vás odhlásí z aplikace. Pokračovat?';
  static const aboutTokenCleared = 'Token vymazán';
  static const aboutClearCoursesTitle = 'Vymazat kurzy?';
  static const aboutClearCoursesMessage =
      'Toto smaže všechny stažené kurzy z tvé lokální knihovny. '
      'Postup v kurzech bude ztracen. Pokračovat?';
  static String aboutCoursesCleared(int count) => 'Smazáno $count kurzů z knihovny';
  static const aboutNoUser = 'Žádný přihlášený uživatel';
  static const aboutFactoryResetTitle = 'Tovární reset?';
  static const aboutFactoryResetMessage =
      'Toto smaže VŠECHNA lokální data: uživatele, kurzy, '
      'postup, záložky, auth token i sync frontu. '
      'Aplikace se vrátí do výchozího stavu jako po čisté instalaci.\n\n'
      'Opravdu pokračovat?';
  static const aboutDeleteAll = 'Smazat vše';
  static String aboutTimeJustNow() => 'právě teď';
  static String aboutTimeSoon() => 'za chvíli';
  static String aboutTimeMinutesAgo(int min, String time) => 'před $min min ($time)';
  static String aboutTimeInMinutes(int min, String time) => 'za $min min ($time)';
  static String aboutTimeToday(String time) => 'dnes $time';

  // ── Theme Selector ──
  static const themeTitle = 'Motiv';
  static const themeDefault = 'Klasický fialový motiv';
  static const themeOcean = 'Modrý motiv inspirovaný oceánem';
  static const themeSunset = 'Teplý motiv v oranžových tónech';
  static const themeCustom = 'Vlastní motiv';
  static const themeCreateNew = 'Vytvořit nový motiv';
  static const themeImportJson = 'Importovat JSON';
  static const themeImportTitle = 'Import motivu';
  static const themeImportHint = 'Vlož JSON motivu…';
  static const themeImportButton = 'Importovat';
  static const themeImportError = 'Neplatný JSON motivu';
  static const themeImportSuccess = 'Motiv úspěšně importován';
  static const themeEditorTitle = 'Editor motivu';
  static const themeEditorName = 'Název motivu';
  static const themeEditorNameHint = 'Můj motiv';
  static const themeEditorSave = 'Uložit motiv';
  static const themeEditorExport = 'Exportovat JSON';
  static const themeEditorExportCopied = 'JSON zkopírován do schránky';
  static const themeEditorDelete = 'Smazat motiv';
  static const themeEditorDeleteConfirm = 'Opravdu chceš smazat tento motiv?';
  static const themeEditorDeleteYes = 'Smazat';
  static const themeEditorCancel = 'Zrušit';
  static const themeEditorConfirm = 'Potvrdit';
  static const themeEditorNameEmpty = 'Zadej název motivu';
  static const themeEditorGroupCoreBrand = 'Hlavní barvy';
  static const themeEditorGroupStatus = 'Stavové barvy';
  static const themeEditorGroupUi = 'UI prvky';
  static const themeEditorGroupCards = 'Karty a pozadí';
  static const themeEditorGroupAvatars = 'Avatary';
  static const themeEditorGroupSubjects = 'Předměty';
  static const themeEditorGroupOther = 'Další';
  static const themeEditorPickColor = 'Vybrat barvu';

  // ── Email Verification ──
  static const emailVerificationTitle = 'Ověření e-mailu';
  static const emailVerificationCodePrompt = 'Zadej 6místný kód z e-mailu';
  static const emailVerificationVerify = 'Ověřit';
  static const emailVerificationResend = 'Nepřišel kód? Odeslat znovu';
  static const emailVerificationSending = 'Odesílám kód...';
  static const emailVerificationOfflineTitle = 'Jsi offline';
  static const emailVerificationOfflineMessage =
      'Pro ověření e-mailu je potřeba připojení k internetu. Můžeš pokračovat bez ověření a ověřit e-mail později.';
  static const emailVerificationRetry = 'Zkusit znovu';
  static const emailVerificationOfflineLabel = 'Bez připojení';

  // ── Email Validation Banner ──
  static const bannerGuestMessage = 'Pro plný přístup se registrujte';
  static const bannerVerifyMessage = 'Ověř svůj e-mail pro plný přístup';
  static const bannerOfflineMessage = 'Připojte se k internetu pro registraci';

  // ── Email Verification Dialog ──
  static const dialogRegistration = 'Registrace';
  static const dialogEmailVerification = 'Ověření e-mailu';
  static const dialogRegistrationSuccess = 'Registrace proběhla úspěšně!';
  static const dialogEmailVerified = 'E-mail byl úspěšně ověřen!';
  static const dialogEmailInputPrompt = 'Zadejte svůj e-mail pro registraci a plný přístup k aplikaci.';
  static const dialogSendCodePrompt = 'Na tento e-mail vám pošleme ověřovací kód.';
  static const dialogSendCode = 'Odeslat kód';
  static const dialogEnterCode = 'Zadejte 6místný kód z e-mailu';
  static const dialogSendNewCode = 'Odeslat nový kód';

  // ── Sync Banner ──
  static const syncSyncing = 'Synchronizace...';
  static const syncDone = 'Synchronizace dokončena';
  static const syncFailed = 'Synchronizace selhala';

  // ── Common Actions ──
  static const actionContinue = 'Pokračovat';
  static const actionCancel = 'Zrušit';
  static const actionDelete = 'Vymazat';
  static const actionBack = 'Zpět';

  // ── Welcome Page ──
  static const welcomeAccessPin = 'Access Free Courses with PIN';

  // ── Login Page ──
  static const loginTitle = 'Přihlášení';
  static const loginEmailPlaceholder = 'student@example.com';

  // ── Auth (shared) ──
  static const authLoginRequired = 'Přidělil ti tento kurz učitel? Nejdříve se přihlas';
  static const authDefaultStudentName = 'Student';

  // ── Profile ──
  static const profileLanguageDefault = 'Čeština';
  static String profileLevelXp(int level, String xp) => 'Level $level • $xp XP';
  static String profileAppVersion(String version) => 'EDU-AI $version';

  // ── Profile Setup Subjects ──
  static const subjectBiology = 'Biologie';
  static const subjectGrammar = 'Gramatika';
  static const subjectLiterature = 'Literatura';
  static const subjectMath = 'Matematika';
  static const subjectChemistry = 'Chemie';
  static const subjectEnglish = 'Angličtina';

  // ── Library (extra) ──
  static const libraryLoginBadge = 'Login';

  // ── Course Detail (extra) ──
  static String courseDurationMin(int min) => '$min min';
  static String courseQuizPrefix(String title) => 'KVÍZ: $title';
  static String courseExerciseSuffix(String title) => '$title - Cvičení';

  // ── Quiz (extra) ──
  static const quizAnswersSaved = 'Odpovědi byly uloženy, děkujeme';

  // ── Achievements (extra) ──
  static String achievementsLvl(int level) => 'Lvl $level';
  // Mock skill categories
  static const skillMolecular = 'Molekulární';
  static const skillEcological = 'Ekologická';
  static const skillEvolutionary = 'Evoluční';
  static const skillCells = 'Buňky';
  static const skillDna = 'DNA';
  static const skillProtein = 'Protein';
  static const skillEcosystems = 'Ekosystémy';
  static const skillProteins = 'Proteiny';

  // ── Chaty Page ──
  static const chatyTitle = 'Chaty';
  static const chatySubtitle = 'Vyber si mentora nebo kouče pro konzultaci';
  static const chatyInfoBanner = 'Všichni AI mentoři a AI učitelé jsou dostupní 24/7 pro pomoc s učením.';
  // Mock chat data
  static const chatMockAiTeacher = 'AI Učitel';
  static const chatMockAiTeacherMsg = 'Dobrá práce na posledním kvízu!';
  static const chatMockMathMentor = 'Mentor Matematika';
  static const chatMockMathMentorMsg = 'Zkus si procvičit derivace';
  static const chatMockTeacherJana = 'Mgr. Jana Nováková';
  static const chatMockTeacherJanaMsg = 'Skvělý rozbor básně!';
  static const chatMockYesterday = 'včera';
  static const chatMockStudyCoach = 'Kouč Pro Studium';
  static const chatMockStartConversation = 'Zahájit konverzaci';
  static const chatMockTeacherPetr = 'Ing. Petr Svoboda';
  static const chatMockTeacherPetrMsg = 'Ty: Potřebuji pomoc s fotosyntézou';
  static const chatMockThreeHoursAgo = 'před 3 hod';
  static const chatMockLanguageMentor = 'Mentor Cizí jazyky';

  // ── Chat Detail Page ──
  static const chatDetailToday = 'Dnes';
  static const chatDetailOnline = 'Online';
  static const chatDetailOffline = 'Offline';
  static const chatDetailInputHint = 'Napiš mi...';
  static const chatDetailHelperText = 'Napiš zprávu nebo polož otázku';
  static const chatDetailMockAiGreeting = 'Ahoj! Jsem tvůj EDU-AI asistent. Jak ti dnes mohu pomoci?';
  static const chatDetailMockUserMsg = 'Můžeš mi vysvětlit buněčné struktury?';
  // Feedback
  static const chatFeedbackTitle = 'Co se ti nelíbilo?';
  static const chatFeedbackSubtitle = 'Tvoje zpětná vazba nám pomůže zlepšit odpovědi';
  static const chatFeedbackSelectReason = 'Vyber důvod';
  static const chatFeedbackDetails = 'Další podrobnosti (volitelné)';
  static const chatFeedbackHint = 'Napiš více o problému...';
  static const chatFeedbackCancel = 'Zrušit';
  static const chatFeedbackSubmit = 'Odeslat';
  static const chatFeedbackThanks = 'Děkujeme za zpětnou vazbu!';
  static const chatFeedbackIncorrect = 'Nesprávné informace';
  static const chatFeedbackIncomplete = 'Neúplná odpověď';
  static const chatFeedbackUnclear = 'Nesrozumitelné vysvětlení';
  static const chatFeedbackInappropriate = 'Nevhodná odpověď';
  static const chatFeedbackOther = 'Jiný důvod';

  // ── Chat UI ──
  static const String chatNewConversation = 'Nová konverzace';
  static const String chatSelectPersona = 'Vyber si mentora';
  static const String chatEmptyState = 'Zatím žádné konverzace.\nZačni chatovat!';
  static const String chatRequiresInternet = 'Chat vyžaduje připojení k internetu';
  static const String chatStreamError = 'Chyba při generování odpovědi';
  static const String chatRetry = 'Zkusit znovu';
  static const String chatDeleteConfirm = 'Opravdu chceš smazat tuto konverzaci?';
  static const String chatDelete = 'Smazat';

  // ── Profile Drawer (extra) ──
  static const drawerNavigation = 'NAVIGACE';
  static const drawerProfile = 'Profil';
  static const drawerMore = 'DALŠÍ';
  static const drawerHelp = 'Nápověda';

  // ── Email Verification Dialog (extra) ──
  static const dialogEmailHint = 'vas@email.cz';

  // ── Widgets: Step Content Renderer ──
  static const stepWriteAnswer = 'Napiš odpověď...';
  static String stepCorrectAnswer(String answer) => 'Správná odpověď: $answer';
  static const stepExplanation = 'Vysvětlení';
  static const stepAudioError = 'Nepodařilo se načíst audio';
  static const stepNumericHint = 'Zadej číslo...';
  static String stepTolerance(String value) => 'Tolerance: ± $value';
  static String stepCorrectNumber(String value) => 'Správná odpověď: $value';
  static const stepVideoError = 'Nepodařilo se načíst video';

  // ── Widgets: Block Step Engine ──
  static const engineCheck = 'Zkontrolovat';
  static const engineNext = 'Další';
  static const engineContinue = 'Pokračovat';
  static const engineSelectAnswer = 'Nejprve vyber odpověď';

  // ── Widgets: Stat Card ──
  static const statStreak = 'Streak';
  static const statDays = 'dní';
  static String statDaysPlural(int days) => days == 1 ? 'den' : 'dní';
  static const statTrophies = 'Trofeje';

  // ── Widgets: Kurzy Course Card ──
  static const courseCardCompleted = 'DOKONČENO';

  // ── Widgets: Promo Card ──
  static const promoDefaultBadge = 'NOVÉ';

  // ── Debug Report ──
  static const aboutSendDebugReport = 'Odeslat diagnostický report';
  static const aboutDebugReportTitle = 'Odeslat report?';
  static const aboutDebugReportMessage =
      'Shromáždí diagnostické informace o aplikaci '
      '(verze, stav databáze, sync fronta, statistiky) '
      'a odešle je vývojářům. Neobsahuje osobní data ani obsah kurzů.';
  static const aboutDebugReportSend = 'Odeslat';
  static const aboutDebugReportSending = 'Odesílám report...';
  static const aboutDebugReportSuccess = 'Diagnostický report byl odeslán';
  static const aboutDebugReportOffline = 'Pro odeslání reportu je potřeba připojení k internetu';
  static String aboutDebugReportError(String e) => 'Nepodařilo se odeslat report: $e';

  // ── Errors ──
  static String genericError(String error) => 'Chyba: $error';
}
