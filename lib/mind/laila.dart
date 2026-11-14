import 'dart:math';

/// LAILA: a small, fully offline emotional-support companion.
/// Prewritten empathetic replies, keyword/intent detection, simple conversation state.
/// She is not a therapist, never diagnoses, and hands over to humans when safety is at stake.

enum LailaLang { en, ar }

enum LailaIntent { crisis, lonely, stress, sleep, exhausted, sad, recovering, breathing, thanks, greeting, other }

/// Simulation scenario Laila can be aware of (set by the simulation center).
enum LailaScenario { none, lonely, preMission, sleep, exhausted, sadness, recovering }

class LailaReply {
  const LailaReply({required this.text, required this.intent, this.urgent = false, this.offerBreathing = false, required this.lang});
  final String text;
  final LailaIntent intent;

  /// True when the safety protocol fired: the UI must show the urgent human-support alert.
  final bool urgent;
  final bool offerBreathing;
  final LailaLang lang;
}

class LailaEngine {
  LailaEngine({Random? random}) : _rng = random ?? Random();
  final Random _rng;

  LailaScenario scenario = LailaScenario.none;
  int _turns = 0;
  LailaIntent? _last;
  bool crisisActive = false;

  void reset() {
    _turns = 0;
    _last = null;
    crisisActive = false;
  }

  // ---------------------------------------------------------------- language
  static LailaLang detectLang(String t) =>
      RegExp(r'[؀-ۿ]').hasMatch(t) ? LailaLang.ar : LailaLang.en;

  static String normalize(String s) {
    var t = s.toLowerCase();
    t = t.replaceAll(RegExp(r'[ً-ٰٟـ]'), ''); // diacritics, tatweel
    t = t.replaceAll(RegExp('[أإآٱ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه');
    t = t.replaceAll(RegExp(r"[’']"), "'");
    return t;
  }

  static String welcome(LailaLang l) => l == LailaLang.en
      ? "Hi, astronaut! I'm Laila. Space missions can be challenging, and sometimes you just need someone to talk to. I'm here to listen. How are you feeling today?"
      : 'أهلاً يا رائد الفضاء! أنا ليلى. المهمات الفضائية قد تكون صعبة، وأحياناً تحتاج فقط لمن يسمعك. أنا هنا لأسمعك. كيف تشعر اليوم؟';

  static const disclaimer = {
    LailaLang.en: 'Laila is a supportive companion, not a therapist, and cannot replace professional care.',
    LailaLang.ar: 'ليلى رفيقة دعم وليست معالجة نفسية، ولا تغني عن الرعاية المتخصصة.',
  };

  // ---------------------------------------------------------------- keywords
  static final _crisis = [
    'kill myself', 'suicid', 'end my life', 'want to die', 'wanna die', 'hurt myself', 'harm myself', 'self-harm', 'self harm',
    "don't want to live", 'dont want to live', 'no reason to live', 'better off dead', 'not safe', 'unsafe', 'end it all',
    'انتحر', 'اقتل نفسي', 'اؤذي نفسي', 'اوذي نفسي', 'اموت', 'عايز اموت', 'عايزه اموت', 'اريد ان اموت', 'انهي حياتي', 'اذي نفسي', 'ايذاء نفسي', 'مش عايز اعيش',
    'مش عايزه اعيش', 'لا اريد ان اعيش', 'مش امان', 'لست بامان', 'انهي كل شيء',
  ].map(normalize).toList();

  static final _kw = <LailaIntent, List<String>>{
    LailaIntent.lonely: [
      'lonely', 'alone', 'miss earth', 'miss home', 'miss my', 'miss you', 'isolated', 'nobody', 'homesick', 'i miss',
      'وحيد', 'وحده', 'وحدتي', 'وحشني', 'وحشتني', 'اشتاق', 'مشتاق', 'اشتقت', 'معزول', 'عزله', 'لا احد',
    ],
    LailaIntent.stress: [
      'stress', 'anxious', 'anxiety', 'worried', 'worry', 'nervous', 'panic', 'scared', 'afraid', 'pressure', 'before the mission',
      'قلق', 'قلقان', 'متوتر', 'توتر', 'خايف', 'خائف', 'ضغط', 'ذعر',
    ],
    LailaIntent.sleep: [
      'sleep', 'insomnia', "can't sleep", 'cant sleep', 'awake all night', 'nightmare', 'tired at night',
      'نوم', 'ارق', 'مش عارف انام', 'لا استطيع النوم', 'كوابيس', 'سهران',
    ],
    LailaIntent.exhausted: [
      'exhausted', 'drained', 'burnt out', 'burned out', 'no energy', 'worn out', 'so tired', 'tired of',
      'مرهق', 'مستنزف', 'تعبان', 'تعبت', 'ارهاق', 'مفيش طاقه', 'لا طاقه',
    ],
    LailaIntent.sad: [
      'sad', 'depressed', 'hopeless', 'empty', 'nothing makes me happy', 'no motivation', 'cry', 'crying', 'worthless', 'numb',
      'حزين', 'زعلان', 'مكتئب', 'اكتئاب', 'مفيش حاجه تفرحني', 'لا شيء يسعدني', 'فاضي', 'ابكي', 'بعيط', 'بلا امل', 'لا دافع',
    ],
    LailaIntent.recovering: [
      'better', 'improving', 'good today', 'feeling good', 'happy', 'hopeful', 'less stressed', 'slept well',
      'احسن', 'افضل', 'تحسنت', 'كويس', 'سعيد', 'مرتاح', 'نمت كويس',
    ],
    LailaIntent.breathing: ['breath', 'breathing', 'calm down', 'relax', 'تنفس', 'اهدا', 'استرخاء'],
    LailaIntent.thanks: ['thank', 'thanks', 'شكرا', 'متشكر', 'ممتن'],
    LailaIntent.greeting: ['hello', 'hi ', 'hey', 'good morning', 'مرحبا', 'اهلا', 'السلام', 'صباح', 'هاي'],
  }.map((k, v) => MapEntry(k, v.map(normalize).toList()));

  LailaIntent detect(String text) {
    final t = ' ${normalize(text)} ';
    if (_crisis.any(t.contains)) return LailaIntent.crisis;
    // Priority: sadness/loneliness/sleep/stress/exhaustion over generic words like "better".
    const order = [
      LailaIntent.sad, LailaIntent.lonely, LailaIntent.sleep, LailaIntent.stress, LailaIntent.exhausted,
      LailaIntent.breathing, LailaIntent.recovering, LailaIntent.thanks, LailaIntent.greeting,
    ];
    var best = LailaIntent.other;
    var bestHits = 0;
    for (final i in order) {
      final hits = _kw[i]!.where(t.contains).length;
      if (hits > bestHits) {
        best = i;
        bestHits = hits;
      }
    }
    return best;
  }

  // ---------------------------------------------------------------- replies
  static const _en = <LailaIntent, List<String>>{
    LailaIntent.lonely: [
      "I'm sorry you're feeling this way. Being so far away from everything familiar can be incredibly difficult. You don't have to pretend you're okay with me. Would you like to tell me what you've been missing the most?",
      "That sounds really lonely. Missing people and places is a very human response to being this far away. Who or what do you think of when the feeling is strongest?",
      "Thank you for telling me. Loneliness on a long mission is common and it does not mean you are weak. Would a call or message to someone you love help today? I can help you plan what to say.",
    ],
    LailaIntent.stress: [
      "That sounds like a lot to carry. Let's slow down together. What is weighing on you the most right now?",
      "Feeling tense before something important makes sense. Would you like to try a short breathing exercise with me, then talk it through?",
      "I hear you. When your mind races, it can help to name the one thing you can control in the next hour. What would that be?",
    ],
    LailaIntent.sleep: [
      "Poor sleep makes everything feel heavier, and sleep is hard to protect on a mission. What do you think keeps you awake: thoughts, noise, light, or your schedule?",
      "I'm sorry you're not sleeping well. A calm wind-down can help: dim the lights, slow your breathing, and let go of tomorrow's tasks for tonight. Want me to guide a short breathing exercise?",
      "Thanks for sharing that. If poor sleep continues for several days, it is worth telling the flight surgeon. Would you like help writing it down for your next check-in?",
    ],
    LailaIntent.exhausted: [
      "You sound worn out. Being tired of everything is a real signal, not a failing. What has drained you the most lately?",
      "That kind of exhaustion is hard. Can you give yourself one small rest today that is only for you, even ten minutes?",
      "I'm glad you said it out loud. Would it help to talk about what you could hand off or postpone this week?",
    ],
    LailaIntent.sad: [
      "I'm really sorry it feels this heavy. You don't have to hide it from me. When did you first notice that things stopped feeling good?",
      "Thank you for trusting me with that. Feeling flat or sad for a while is something to take seriously and kindly. Have you been able to talk to anyone on the crew?",
      "I hear how hard this is. If this feeling has lasted for days, please consider speaking with the flight surgeon or psychological support. I'm here with you in the meantime. What would feel even a little bit better right now?",
    ],
    LailaIntent.recovering: [
      "I'm really glad to hear that. What do you think helped the most? It's good to remember it for harder days.",
      "That's wonderful progress. Small improvements count. Is there something you want to keep doing to protect this feeling?",
      "It's good to hear you sounding lighter. Let's notice what is working so you can lean on it again.",
    ],
    LailaIntent.breathing: [
      "Let's breathe together. In through your nose for 4 counts, hold for 4, out slowly for 6. Repeat about five times. I'll be here.",
    ],
    LailaIntent.thanks: [
      "You're very welcome. I'm here whenever you want to talk.",
      "Anytime. Taking a moment for yourself matters.",
    ],
    LailaIntent.greeting: [
      "Hello! I'm glad you're here. How are you feeling today?",
      "Hi there. What's on your mind today?",
    ],
    LailaIntent.other: [
      "I'm listening. Could you tell me a little more about how that feels?",
      "Thank you for sharing. What part of this is hardest for you right now?",
      "I want to understand. How has this been affecting your days?",
    ],
  };

  static const _ar = <LailaIntent, List<String>>{
    LailaIntent.lonely: [
      'أنا آسفة لأنك تشعر بهذا. البعد عن كل ما هو مألوف صعب جداً. لا داعي أن تتظاهر أنك بخير معي. هل تحب أن تخبرني ما الذي تفتقده أكثر؟',
      'يبدو أنك تشعر بوحدة حقيقية. الاشتياق للناس والأماكن شعور إنساني طبيعي عندما تكون بعيداً هكذا. من تفكر فيه عندما يشتد هذا الشعور؟',
      'شكراً لأنك أخبرتني. الوحدة في المهمات الطويلة شائعة ولا تعني أنك ضعيف. هل تفيدك مكالمة أو رسالة لشخص تحبه اليوم؟ أستطيع مساعدتك فيما تقوله.',
    ],
    LailaIntent.stress: [
      'يبدو أنك تحمل الكثير. دعنا نبطئ معاً. ما الذي يثقل عليك أكثر الآن؟',
      'من الطبيعي أن تتوتر قبل أمر مهم. هل تريد أن نجرب تمرين تنفس قصيراً ثم نتحدث؟',
      'أسمعك. عندما يتسارع التفكير يفيد أن تحدد شيئاً واحداً تستطيع التحكم فيه خلال الساعة القادمة. ما هو؟',
    ],
    LailaIntent.sleep: [
      'قلة النوم تجعل كل شيء أثقل، وحماية النوم صعبة في المهمات. ما الذي يوقظك برأيك: الأفكار أم الضوضاء أم الإضاءة أم الجدول؟',
      'آسفة لأنك لا تنام جيداً. قد يفيد تهدئة المساء: إضاءة خافتة وتنفس بطيء وترك مهام الغد لليلة. هل تريد أن أرشدك لتمرين تنفس قصير؟',
      'شكراً لمشاركتك. إذا استمر الأرق عدة أيام فمن المهم إخبار جراح الطيران. هل أساعدك في كتابته لتقرير اليوم؟',
    ],
    LailaIntent.exhausted: [
      'تبدو منهكاً. الشعور بالتعب من كل شيء إشارة حقيقية وليس فشلاً. ما الذي أرهقك أكثر مؤخراً؟',
      'هذا النوع من الإرهاق صعب. هل تستطيع أن تمنح نفسك استراحة صغيرة اليوم ولو عشر دقائق؟',
      'سعيدة أنك قلتها بصوت عالٍ. هل يفيد أن نتحدث عمّا يمكنك تأجيله أو تفويضه هذا الأسبوع؟',
    ],
    LailaIntent.sad: [
      'أنا آسفة جداً أن الأمر ثقيل هكذا. لا داعي لإخفائه عني. متى لاحظت أن الأشياء لم تعد تشعرك بالسعادة؟',
      'شكراً لثقتك بي. الحزن أو الفتور لفترة يستحق أن نأخذه بجدية ولطف. هل استطعت التحدث مع أحد من الطاقم؟',
      'أفهم كم هو صعب. إذا استمر هذا الشعور لعدة أيام فأرجو أن تتحدث مع جراح الطيران أو الدعم النفسي. أنا معك الآن. ما الذي قد يريحك ولو قليلاً؟',
    ],
    LailaIntent.recovering: [
      'يسعدني سماع ذلك. ما الذي ساعدك أكثر برأيك؟ جميل أن نتذكره للأيام الأصعب.',
      'هذا تقدم رائع. التحسن الصغير مهم. هل هناك شيء تريد أن تستمر فيه لتحافظ على هذا الشعور؟',
      'جميل أن أسمعك أخف. دعنا نلاحظ ما ينفع لتعتمد عليه مرة أخرى.',
    ],
    LailaIntent.breathing: [
      'لنتنفس معاً. شهيق من الأنف لأربع عدّات، احبس أربعاً، ثم زفير بطيء لست. كرر حوالي خمس مرات. أنا معك.',
    ],
    LailaIntent.thanks: ['على الرحب والسعة. أنا هنا متى أردت التحدث.', 'في أي وقت. أخذ لحظة لنفسك مهم.'],
    LailaIntent.greeting: ['أهلاً! سعيدة بوجودك. كيف تشعر اليوم؟', 'مرحباً. ما الذي يشغل بالك اليوم؟'],
    LailaIntent.other: [
      'أنا أسمعك. هل تخبرني أكثر عن شعورك؟',
      'شكراً لمشاركتك. ما أصعب جزء في هذا الآن؟',
      'أريد أن أفهم. كيف أثّر هذا على أيامك؟',
    ],
  };

  static const _crisisEn =
      "I'm really glad you told me, and I'm taking this seriously. You deserve support from a person right now. "
      'Please contact the mission medical officer or mission control immediately, or go to the nearest crewmate and tell them how you feel. '
      "I'm not a therapist and I can't keep you safe alone. Please don't stay by yourself with this.";
  static const _crisisAr =
      'أنا ممتنة لأنك أخبرتني، وآخذ الأمر بجدية. أنت تستحق دعماً من إنسان الآن. '
      'من فضلك تواصل فوراً مع الطبيب المسؤول عن المهمة أو مركز التحكم، أو اذهب لأقرب زميل في الطاقم وأخبره بما تشعر به. '
      'أنا لست معالجة نفسية ولا أستطيع حمايتك وحدي. أرجوك لا تبقَ وحدك مع هذا الشعور.';

  static const _ctxEn = {
    LailaScenario.lonely: 'I know the distance from Earth has been weighing on you. ',
    LailaScenario.preMission: 'I know a big moment is coming up. ',
    LailaScenario.sleep: 'I know sleep has been a struggle lately. ',
    LailaScenario.exhausted: 'I know you have been running on empty. ',
    LailaScenario.sadness: 'I know things have felt heavy for a while. ',
    LailaScenario.recovering: 'I can see things have been slowly getting better. ',
  };
  static const _ctxAr = {
    LailaScenario.lonely: 'أعرف أن البعد عن الأرض يثقل عليك. ',
    LailaScenario.preMission: 'أعرف أن لحظة مهمة تقترب. ',
    LailaScenario.sleep: 'أعرف أن النوم كان صعباً مؤخراً. ',
    LailaScenario.exhausted: 'أعرف أنك تعمل بطاقة شبه فارغة. ',
    LailaScenario.sadness: 'أعرف أن الأمور تبدو ثقيلة منذ فترة. ',
    LailaScenario.recovering: 'أرى أن الأمور تتحسن ببطء. ',
  };

  String _pick(List<String> v, {int avoid = -1}) {
    if (v.length == 1) return v.first;
    // Rotate by turn so the demo conversation progresses, with a little randomness.
    final i = (_turns + _rng.nextInt(v.length)) % v.length;
    return v[i == avoid ? (i + 1) % v.length : i];
  }

  LailaReply respond(String text, {LailaLang? lang}) {
    final l = lang ?? detectLang(text);
    final intent = detect(text);
    _turns++;
    if (intent == LailaIntent.crisis) {
      crisisActive = true;
      _last = intent;
      return LailaReply(text: l == LailaLang.en ? _crisisEn : _crisisAr, intent: intent, urgent: true, lang: l);
    }
    // While the safety protocol is active, no ordinary motivational replies.
    if (crisisActive) {
      return LailaReply(
        text: l == LailaLang.en
            ? 'I am still here. Please reach the mission medical officer or mission control now, or tell a crewmate. A person needs to be with you. Is someone with you right now?'
            : 'ما زلت هنا. من فضلك تواصل مع الطبيب المسؤول أو مركز التحكم الآن، أو أخبر زميلاً. يجب أن يكون معك شخص. هل معك أحد الآن؟',
        intent: LailaIntent.crisis,
        urgent: true,
        lang: l,
      );
    }
    var effective = intent;
    if (intent == LailaIntent.other || intent == LailaIntent.greeting) {
      effective = switch (scenario) {
        LailaScenario.lonely => LailaIntent.lonely,
        LailaScenario.preMission => LailaIntent.stress,
        LailaScenario.sleep => LailaIntent.sleep,
        LailaScenario.exhausted => LailaIntent.exhausted,
        LailaScenario.sadness => LailaIntent.sad,
        LailaScenario.recovering => LailaIntent.recovering,
        LailaScenario.none => intent,
      };
    }
    final table = l == LailaLang.en ? _en : _ar;
    var body = (effective == LailaIntent.lonely && _last == null && intent == LailaIntent.lonely)
        ? table[LailaIntent.lonely]!.first // the first lonely reply is the documented demo response
        : _pick(table[effective]!);
    if (scenario != LailaScenario.none && _last == null && effective != LailaIntent.breathing && intent != LailaIntent.lonely) {
      body = '${(l == LailaLang.en ? _ctxEn : _ctxAr)[scenario]}$body';
    }
    _last = effective;
    return LailaReply(
      text: body,
      intent: effective,
      offerBreathing: effective == LailaIntent.stress || effective == LailaIntent.sleep || effective == LailaIntent.breathing,
      lang: l,
    );
  }
}
