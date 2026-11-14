/// Structured first-aid knowledge base for ASTRO EMERGENCY RESPONSE.
///
/// Rules:
///  * Nothing here is generated at run time. Every instruction is a fixed entry
///    with sources.
///  * It is general first-aid guidance for decision support. It is NOT an
///    approved NASA medical system and has NOT been clinically reviewed
///    (see [kDisclaimer] and [Protocol.reviewStatus]).
///  * No medication, dose or diagnosis is ever produced. Where a medicine is
///    relevant, the entry says to use it only as directed by the mission medical
///    officer under an approved protocol.
///  * Microgravity and EVA are different from ground first aid. Where we do not
///    hold a verified spaceflight-specific procedure the entry says so and
///    refers to the approved mission checklist.
library;

class Tx {
  const Tx(this.en, this.ar);
  final String en, ar;
  String of(bool arabic) => arabic ? ar : en;
}

enum EmergencyKind { syncope, hypoxia, chestPain, arrhythmia, respiratory, stroke, dehydration, heat, radiation, allergy, psychological }

/// Where the astronaut is. It changes the advice.
enum Place { cabin, eva, ground }

/// Who is reading: the affected astronaut, or a crewmate helping.
enum Role { self, helper }

const kDisclaimer = Tx(
  'Decision support only. This is not an official NASA or clinical medical system. Guidance is general first-aid reference information that has not been clinically reviewed. Follow the approved mission medical checklists and the instructions of the mission medical officer and mission control.',
  'دعم قرار فقط. هذا ليس نظامًا طبيًا رسميًا من ناسا أو نظامًا سريريًا. الإرشادات معلومات إسعاف أولي عامة لم تُراجَع سريريًا. اتبع قوائم المراجعة الطبية المعتمدة للمهمة وتعليمات الطبيب المسؤول ومركز التحكم.',
);

const kSpaceFallback = Tx(
  'No verified spaceflight-specific procedure is held in this app for this step. Use the approved mission checklist and ask mission medical support. Ground first-aid steps are shown as general reference only.',
  'لا يوجد في التطبيق إجراء مُتحقَّق منه خاص بالفضاء لهذه الخطوة. استخدم قائمة المراجعة المعتمدة للمهمة واطلب الدعم الطبي. خطوات الإسعاف الأرضي معروضة كمرجع عام فقط.',
);

class Source {
  const Source({required this.org, required this.doc, required this.url, this.published, required this.checked});
  final String org, doc, url;

  /// Publication or revision date exactly as the source states it, or null if the source page does not state one.
  final String? published;

  /// What was actually checked, and when.
  final String checked;
}

const _aha = Source(
  org: 'American Heart Association and American Red Cross',
  doc: '2024 Guidelines for First Aid',
  url: 'https://cpr.heart.org/en/resuscitation-science/2024-first-aid-guidelines',
  published: '2024 (Focused Update)',
  checked: '2026-11-14: page opened; sections on presyncope, chest pain, stroke, anaphylaxis and asthma are present. Step wording is not copied from it and has not been clinically reviewed.',
);
const _nasaCare = Source(
  org: 'NASA',
  doc: 'In-Flight Medical Care',
  url: 'https://www.nasa.gov/ochmo/health-and-medical-systems/in-flight-medical-care/',
  published: 'January 7, 2026 (page metadata; last updated July 17, 2026)',
  checked: '2026-11-14: page opened. It describes in-flight medical care and ground medical support. It contains no step-by-step procedures.',
);
const _nasaOps = Source(
  org: 'NASA',
  doc: 'Medical Operations',
  url: 'https://www.nasa.gov/reference/medical-operations/',
  checked: '2026-11-14: listed as a reference pointer. Not individually reviewed for step content.',
);
const _nasaStd = Source(
  org: 'NASA',
  doc: 'Human Spaceflight and Aviation Standards',
  url: 'https://www.nasa.gov/ochmo/human-spaceflight-and-aviation-standards/',
  checked: '2026-11-14: listed as a reference pointer. Not individually reviewed for step content.',
);

class Guide {
  const Guide(this.title, this.steps);
  final Tx title;
  final List<Tx> steps;
}

class Protocol {
  const Protocol({
    required this.kind,
    required this.title,
    required this.possibility,
    required this.criteria,
    required this.self,
    required this.helper,
    required this.place,
    required this.avoid,
    required this.escalate,
    required this.space,
    required this.sources,
    this.severity = 3,
  });
  final EmergencyKind kind;
  final Tx title;

  /// How the condition is named on screen: always a possibility, never a diagnosis.
  final Tx possibility;
  final List<Tx> criteria;
  final Guide self, helper;

  /// One step that depends on where the astronaut is.
  final Map<Place, Tx> place;
  final List<Tx> avoid, escalate;
  final Tx space;
  final List<Source> sources;

  /// 1 attention, 2 serious, 3 critical: a default; the live severity comes from the data.
  final int severity;
  String get reviewStatus => 'Not clinically reviewed';
  Guide guide(Role r) => r == Role.self ? self : helper;
}

const _contactMcc = Tx('Contact mission medical support now and tell them what you see and when it started.', 'تواصل مع الدعم الطبي للمهمة الآن وأخبرهم بما تراه ومتى بدأ.');
const _recordTime = Tx('Note the time symptoms began and the latest sensor readings.', 'سجّل وقت بدء الأعراض وآخر قراءات الحساسات.');

const kProtocols = <Protocol>[
  Protocol(
    kind: EmergencyKind.syncope,
    title: Tx('Fainting or near-fainting', 'إغماء أو شعور وشيك بالإغماء'),
    possibility: Tx('Possible fainting (syncope). Not a diagnosis.', 'احتمال إغماء. وليس تشخيصًا.'),
    criteria: [
      Tx('Dizziness, sudden weakness or vision changes', 'دوخة أو ضعف مفاجئ أو اضطراب في الرؤية'),
      Tx('Abnormal heart rate or a sudden drop in movement', 'نبض غير طبيعي أو توقف مفاجئ للحركة'),
    ],
    self: Guide(Tx('If you feel you might faint', 'لو حاسس إنك هتُغمى عليك'), [
      Tx('Stop what you are doing and tell a crewmate now.', 'أوقف ما تفعله وأخبر زميلًا فورًا.'),
      Tx('Secure yourself so you cannot fall or float into equipment.', 'ثبّت نفسك حتى لا تسقط أو تصطدم بالمعدات.'),
      Tx('Breathe slowly and stay still until the feeling passes.', 'تنفس ببطء وابقَ ساكنًا حتى يزول الشعور.'),
      _contactMcc,
    ]),
    helper: Guide(Tx('If the astronaut has fainted', 'لو الرائد فقد الوعي'), [
      Tx('Make sure the area is safe for you and for them. Secure them so they cannot hit equipment.', 'تأكد أن المكان آمن لك ولهم، وثبّته حتى لا يصطدم بالمعدات.'),
      Tx('Check responsiveness: tap the shoulders and call their name loudly.', 'تحقق من الاستجابة: اضغط على الكتفين وناده بصوت عالٍ.'),
      Tx('Check breathing for no more than 10 seconds. Normal breathing means regular breaths. Gasping or no breathing is not normal.', 'تحقق من التنفس في أقل من 10 ثوانٍ. التنفس الطبيعي منتظم، أما اللهاث أو انعدام التنفس فغير طبيعي.'),
      Tx('If not breathing normally: call for help, get the defibrillator, and start CPR using the approved mission procedure.', 'لو لا يتنفس بشكل طبيعي: اطلب المساعدة وأحضر جهاز الصدمات وابدأ الإنعاش بالإجراء المعتمد للمهمة.'),
      _contactMcc,
    ]),
    place: {
      Place.ground: Tx('With gravity: lie down and raise the legs if the person is breathing normally.', 'مع وجود الجاذبية: اجعله يستلقي وارفع الساقين لو كان يتنفس بشكل طبيعي.'),
      Place.cabin: Tx('In microgravity, lying down with raised legs does not apply. Restrain the person and follow the approved microgravity procedure.', 'في انعدام الوزن لا ينطبق الاستلقاء ورفع الساقين. ثبّت الشخص واتبع إجراء انعدام الوزن المعتمد.'),
      Place.eva: Tx('On EVA: do not tell an impaired astronaut to move. Notify the crew and mission control and follow the approved EVA contingency procedure.', 'أثناء المهمة الخارجية: لا تطلب من رائد غير قادر أن يتحرك. أبلغ الطاقم ومركز التحكم واتبع إجراء الطوارئ المعتمد.'),
    },
    avoid: [
      Tx('Do not give food or drink to someone who is not fully awake.', 'لا تعطِ طعامًا أو شرابًا لمن ليس مستيقظًا تمامًا.'),
      Tx('Do not leave the person alone.', 'لا تترك الشخص وحده.'),
    ],
    escalate: [
      Tx('Not responsive, or not breathing normally: emergency now.', 'غير مستجيب أو لا يتنفس بشكل طبيعي: طوارئ فورًا.'),
      Tx('Fainting that repeats, or comes with chest pain or breathing trouble.', 'إغماء يتكرر أو مع ألم صدر أو صعوبة تنفس.'),
    ],
    space: Tx('Ground first aid (lie down, raise legs) depends on gravity. Spaceflight handling follows NASA procedures.', 'إسعاف الأرض (الاستلقاء ورفع الساقين) يعتمد على الجاذبية. أما في الفضاء فتُتبع إجراءات ناسا.'),
    sources: [_aha, _nasaCare, _nasaOps],
  ),
  Protocol(
    kind: EmergencyKind.hypoxia,
    title: Tx('Low oxygen (suspected hypoxia)', 'نقص الأكسجين (اشتباه)'),
    possibility: Tx('Possible low oxygen. A low SpO₂ alone does not show the cause.', 'احتمال نقص أكسجين. انخفاض SpO₂ وحده لا يحدد السبب.'),
    criteria: [
      Tx('Falling SpO₂ with shortness of breath, confusion, headache or unusual fatigue', 'هبوط SpO₂ مع ضيق نفس أو تشوش أو صداع أو إرهاق غير معتاد'),
      Tx('A change in breathing rate', 'تغيّر في معدل التنفس'),
    ],
    self: Guide(Tx('If you feel short of breath or confused', 'لو حاسس بضيق نفس أو تشوش'), [
      Tx('Stop exertion and sit or secure yourself in a stable position.', 'أوقف المجهود واجلس أو ثبّت نفسك في وضع مستقر.'),
      Tx('Check the cabin oxygen, total pressure and CO₂ indicators and any alarms. Low pressure, low oxygen and high CO₂ are different causes.', 'افحص مؤشرات الأكسجين والضغط الكلي وثاني أكسيد الكربون والإنذارات. نقص الضغط ونقص الأكسجين وارتفاع CO₂ أسباب مختلفة.'),
      Tx('Check the sensor in parallel: fit, cold fingers, movement. Do not wait for this before acting.', 'افحص الحساس بالتوازي: الإحكام وبرودة الأصابع والحركة. لا تنتظر ذلك قبل التصرف.'),
      Tx('Start the approved oxygen and life-support emergency protocol if the indicators are abnormal or symptoms are severe.', 'ابدأ بروتوكول الطوارئ المعتمد للأكسجين ودعم الحياة لو كانت المؤشرات غير طبيعية أو الأعراض شديدة.'),
      _contactMcc,
    ]),
    helper: Guide(Tx('If the astronaut may be short of oxygen', 'لو الرائد قد يعاني من نقص أكسجين'), [
      Tx('Check your own breathing and the environment alarms first, so you do not become a second casualty.', 'افحص تنفسك وإنذارات البيئة أولًا حتى لا تصبح مصابًا ثانيًا.'),
      Tx('Keep the person calm and still. Check responsiveness and breathing.', 'اجعل الشخص هادئًا وساكنًا. تحقق من الاستجابة والتنفس.'),
      Tx('Start the approved oxygen and life-support emergency protocol and call mission control.', 'ابدأ بروتوكول الطوارئ المعتمد للأكسجين واتصل بمركز التحكم.'),
      Tx('If not breathing normally, start CPR using the approved mission procedure.', 'لو لا يتنفس بشكل طبيعي فابدأ الإنعاش بالإجراء المعتمد للمهمة.'),
    ]),
    place: {
      Place.cabin: Tx('In the cabin: move to the nearest area the life-support readout shows as safe, or use emergency oxygen as the approved procedure directs.', 'داخل المركبة: انتقل لأقرب منطقة تُظهر قراءات دعم الحياة أنها آمنة، أو استخدم أكسجين الطوارئ كما يحدد الإجراء المعتمد.'),
      Place.eva: Tx('On EVA: check suit pressure and oxygen status, tell the crew and mission control, and follow the approved EVA contingency procedure. Do not improvise a return path.', 'في المهمة الخارجية: افحص ضغط وأكسجين البدلة، وأبلغ الطاقم ومركز التحكم، واتبع إجراء الطوارئ المعتمد. لا ترتجل مسار عودة.'),
      Place.ground: Tx('On the ground: move to fresh air if the air may be bad, sit upright, and call emergency services.', 'على الأرض: انتقل إلى هواء نقي لو كان الهواء سيئًا، واجلس معتدلًا، واتصل بالإسعاف.'),
    },
    avoid: [
      Tx('Do not assume the cause from SpO₂ alone.', 'لا تفترض السبب من SpO₂ وحده.'),
      Tx('Do not keep exerting yourself to test the reading.', 'لا تواصل المجهود لاختبار القراءة.'),
    ],
    escalate: [
      Tx('SpO₂ keeps falling, or severe breathlessness, confusion or blue lips.', 'استمرار هبوط SpO₂ أو ضيق نفس شديد أو تشوش أو زرقة الشفاه.'),
      Tx('Any suspected life-support failure.', 'أي اشتباه في عطل بدعم الحياة.'),
    ],
    space: Tx('Reduced oxygen, reduced cabin pressure and high CO₂ are separate hazards. Use the cabin readouts and the approved procedure.', 'نقص الأكسجين ونقص ضغط المقصورة وارتفاع CO₂ مخاطر مختلفة. استخدم قراءات المقصورة والإجراء المعتمد.'),
    sources: [_nasaCare, _nasaStd, _nasaOps],
  ),
  Protocol(
    kind: EmergencyKind.chestPain,
    title: Tx('Chest pain (suspected heart problem)', 'ألم في الصدر (اشتباه مشكلة قلبية)'),
    possibility: Tx('Possible heart-related emergency. Not a diagnosis; it needs trained assessment.', 'احتمال حالة قلبية طارئة. وليس تشخيصًا، ويحتاج تقييمًا من مختص.'),
    criteria: [
      Tx('Chest pain or pressure, possibly spreading to arm, back, jaw or neck', 'ألم أو ضغط بالصدر قد ينتشر للذراع أو الظهر أو الفك أو الرقبة'),
      Tx('Shortness of breath, cold sweat, nausea or unusual fatigue', 'ضيق نفس أو عرق بارد أو غثيان أو إرهاق غير معتاد'),
    ],
    self: Guide(Tx('If you have chest pain or pressure', 'لو عندك ألم أو ضغط في الصدر'), [
      Tx('Stop all activity and rest in the most comfortable stable position.', 'أوقف كل نشاط واسترح في أكثر وضع مريح ومستقر.'),
      Tx('Call a crewmate and mission medical support now. Do not wait to see if it passes.', 'نادِ زميلًا واتصل بالدعم الطبي الآن. لا تنتظر لترى هل يزول.'),
      Tx('Ask someone to bring the defibrillator and medical kit.', 'اطلب من أحدهم إحضار جهاز الصدمات والحقيبة الطبية.'),
      Tx('Do not take any medicine unless the mission medical officer directs it under an approved protocol.', 'لا تتناول أي دواء إلا بتوجيه الطبيب المسؤول وفق بروتوكول معتمد.'),
    ]),
    helper: Guide(Tx('If a crewmate has chest pain', 'لو زميل عنده ألم صدر'), [
      Tx('Have them stop and rest in the position that is easiest for breathing. Stay with them.', 'اجعله يتوقف ويستريح في الوضع الأسهل للتنفس. ابقَ معه.'),
      Tx('Call mission medical support and bring the defibrillator.', 'اتصل بالدعم الطبي وأحضر جهاز الصدمات.'),
      Tx('Watch responsiveness and breathing. If unresponsive and not breathing normally, start CPR and use the defibrillator per the approved procedure.', 'راقب الاستجابة والتنفس. لو غير مستجيب ولا يتنفس بشكل طبيعي فابدأ الإنعاش واستخدم جهاز الصدمات بالإجراء المعتمد.'),
    ]),
    place: {
      Place.cabin: Tx('In the cabin: restrain the person comfortably and bring the medical kit to them rather than moving them.', 'داخل المركبة: ثبّت الشخص براحة وأحضر الحقيبة الطبية إليه بدل نقله.'),
      Place.eva: Tx('On EVA: do not tell an impaired astronaut to move. Alert the crew and mission control and follow the approved EVA contingency procedure.', 'في المهمة الخارجية: لا تطلب من رائد غير قادر أن يتحرك. أبلغ الطاقم ومركز التحكم واتبع إجراء الطوارئ المعتمد.'),
      Place.ground: Tx('On the ground: sit or recline comfortably and call emergency services immediately.', 'على الأرض: اجلس أو استلقِ براحة واتصل بالإسعاف فورًا.'),
    },
    avoid: [
      Tx('Do not take medicine without medical authorization.', 'لا تتناول دواءً دون تصريح طبي.'),
      Tx('Do not keep working or walk it off.', 'لا تواصل العمل ولا تحاول "المشي" حتى يزول.'),
    ],
    escalate: [
      Tx('Any chest pain with breathlessness, sweating, fainting or abnormal heart rate.', 'أي ألم صدر مع ضيق نفس أو عرق أو إغماء أو نبض غير طبيعي.'),
    ],
    space: Tx('Spaceflight cardiac emergencies follow mission medical procedures and ground medical support.', 'الطوارئ القلبية في الفضاء تتبع الإجراءات الطبية للمهمة ودعم الأرض.'),
    sources: [_aha, _nasaCare, _nasaOps],
  ),
  Protocol(
    kind: EmergencyKind.arrhythmia,
    title: Tx('Abnormal heart rate or rhythm', 'نبض أو إيقاع قلب غير طبيعي'),
    possibility: Tx('Abnormal heart-rate reading. This is not a confirmed arrhythmia; that needs ECG and expert interpretation.', 'قراءة نبض غير طبيعية. وليست عدم انتظام مؤكدًا، فذلك يحتاج تخطيط قلب وتفسيرًا من مختص.'),
    criteria: [
      Tx('Heart rate far above or below the personal baseline', 'نبض أعلى أو أقل بكثير من خطك الشخصي'),
      Tx('Palpitations with dizziness or chest pain', 'خفقان مع دوخة أو ألم صدر'),
    ],
    self: Guide(Tx('If your heart rate feels or reads abnormal', 'لو نبضك يبدو أو يُقرأ غير طبيعي'), [
      Tx('Stop activity and rest. Check the sensor fit and re-measure to rule out a bad reading.', 'أوقف النشاط واسترح. افحص إحكام الحساس وأعد القياس لاستبعاد قراءة خاطئة.'),
      Tx('Note symptoms: dizziness, chest pain, breathlessness, fainting.', 'دوّن الأعراض: دوخة أو ألم صدر أو ضيق نفس أو إغماء.'),
      Tx('Send heart rate, symptoms and time to mission medical support.', 'أرسل النبض والأعراض والوقت للدعم الطبي.'),
    ]),
    helper: Guide(Tx('If a crewmate has an abnormal heart rate', 'لو زميل نبضه غير طبيعي'), [
      Tx('Keep them resting and stay with them.', 'اجعله يستريح وابقَ معه.'),
      Tx('Check responsiveness and breathing. Fainting, chest pain or trouble breathing makes it an emergency.', 'تحقق من الاستجابة والتنفس. الإغماء أو ألم الصدر أو صعوبة التنفس تجعلها طارئة.'),
      Tx('Contact mission medical support with the readings.', 'اتصل بالدعم الطبي مع القراءات.'),
    ]),
    place: {
      Place.cabin: Tx('In the cabin: secure the person and keep the sensor on while medical support reviews the data.', 'داخل المركبة: ثبّت الشخص وأبقِ الحساس عليه بينما يراجع الدعم الطبي البيانات.'),
      Place.eva: Tx('On EVA: report to the crew and mission control and follow the approved EVA contingency procedure.', 'في المهمة الخارجية: أبلغ الطاقم ومركز التحكم واتبع إجراء الطوارئ المعتمد.'),
      Place.ground: Tx('On the ground: sit, rest, and seek medical care if symptoms are present.', 'على الأرض: اجلس واسترح واطلب رعاية طبية لو توجد أعراض.'),
    },
    avoid: [
      Tx('Do not name a specific arrhythmia from a wristband reading.', 'لا تسمِّ نوع اضطراب إيقاع بعينه من قراءة سوار.'),
      Tx('Do not take medicine without medical authorization.', 'لا تتناول دواءً دون تصريح طبي.'),
    ],
    escalate: [
      Tx('Abnormal rate with fainting, chest pain or breathlessness.', 'نبض غير طبيعي مع إغماء أو ألم صدر أو ضيق نفس.'),
    ],
    space: Tx('Spaceflight interpretation needs ECG data and a validated method; neither is available in this app.', 'التفسير في الفضاء يحتاج بيانات تخطيط قلب وطريقة مُعتمدة، وكلاهما غير متاح في هذا التطبيق.'),
    sources: [_aha, _nasaCare],
    severity: 2,
  ),
  Protocol(
    kind: EmergencyKind.respiratory,
    title: Tx('Breathing emergency or choking', 'طوارئ تنفس أو اختناق'),
    possibility: Tx('Possible breathing emergency (e.g. asthma attack or blocked airway). Not a diagnosis.', 'احتمال طارئ تنفسي (مثل نوبة ربو أو انسداد مجرى الهواء). وليس تشخيصًا.'),
    criteria: [
      Tx('Severe shortness of breath or noisy, labored breathing', 'ضيق نفس شديد أو تنفس مجهد وصاخب'),
      Tx('Cannot speak, cough or breathe', 'لا يستطيع الكلام أو السعال أو التنفس'),
    ],
    self: Guide(Tx('If you are struggling to breathe', 'لو بتجد صعوبة في التنفس'), [
      Tx('Stop activity and sit upright or secure yourself. Try to stay calm and breathe slowly.', 'أوقف النشاط واجلس معتدلًا أو ثبّت نفسك. حاول أن تبقى هادئًا وتتنفس ببطء.'),
      Tx('Signal for help right away. If you cannot speak, use the emergency alarm.', 'اطلب المساعدة فورًا. لو لا تستطيع الكلام فاستخدم إنذار الطوارئ.'),
      Tx('If you have a prescribed reliever, use it only as your mission medical protocol allows.', 'لو معك دواء موصوف فاستخدمه فقط بالقدر الذي يسمح به بروتوكول المهمة الطبي.'),
      _contactMcc,
    ]),
    helper: Guide(Tx('If a crewmate cannot breathe or may be choking', 'لو زميل لا يستطيع التنفس أو قد يختنق'), [
      Tx('Ask: "Are you choking?" If they can cough or speak, encourage coughing and stay with them.', 'اسأل: "هل تختنق؟" لو يستطيع السعال أو الكلام فشجّعه على السعال وابقَ معه.'),
      Tx('If they cannot cough, speak or breathe: give 5 firm back blows between the shoulder blades, then 5 abdominal thrusts, and repeat. Restrain yourself and them first in microgravity.', 'لو لا يستطيع السعال أو الكلام أو التنفس: وجّه 5 ضربات قوية بين لوحي الكتف ثم 5 ضغطات على البطن وكرر. في انعدام الوزن ثبّت نفسك وثبّته أولًا.'),
      Tx('If they become unresponsive and are not breathing normally, start CPR per the approved procedure and call mission control.', 'لو فقد الاستجابة ولا يتنفس بشكل طبيعي فابدأ الإنعاش بالإجراء المعتمد واتصل بمركز التحكم.'),
    ]),
    place: {
      Place.cabin: Tx('In the cabin: anchor yourself before any back blows or thrusts. Microgravity technique follows the approved procedure.', 'داخل المركبة: ثبّت نفسك قبل أي ضربات أو ضغطات. أسلوب انعدام الوزن يتبع الإجراء المعتمد.'),
      Place.eva: Tx('On EVA: a suit breathing problem is a suit emergency. Alert the crew and mission control and follow the approved EVA contingency procedure.', 'في المهمة الخارجية: مشكلة التنفس في البدلة طارئ للبدلة. أبلغ الطاقم ومركز التحكم واتبع إجراء الطوارئ المعتمد.'),
      Place.ground: Tx('On the ground: call emergency services at once for severe breathing trouble.', 'على الأرض: اتصل بالإسعاف فورًا عند صعوبة التنفس الشديدة.'),
    },
    avoid: [
      Tx('Do not give water or food to someone who is choking.', 'لا تعطِ ماءً أو طعامًا لمن يختنق.'),
      Tx('Do not slap the back if the person can still cough effectively.', 'لا تضرب الظهر لو كان الشخص ما زال يسعل بفاعلية.'),
    ],
    escalate: [
      Tx('Cannot speak or breathe, blue lips, or becoming unresponsive.', 'لا يستطيع الكلام أو التنفس أو زرقة الشفاه أو فقدان الاستجابة.'),
    ],
    space: Tx('Abdominal thrusts and CPR need restraint in microgravity. Follow the approved mission technique.', 'ضغطات البطن والإنعاش تحتاجان تثبيتًا في انعدام الوزن. اتبع أسلوب المهمة المعتمد.'),
    sources: [_aha, _nasaCare, _nasaOps],
  ),
  Protocol(
    kind: EmergencyKind.stroke,
    title: Tx('Stroke warning signs', 'علامات السكتة الدماغية'),
    possibility: Tx('Possible stroke warning signs. Not a diagnosis; time matters.', 'علامات محتملة لسكتة دماغية. وليست تشخيصًا، والوقت مهم.'),
    criteria: [
      Tx('Face drooping, arm weakness, speech difficulty (FAST)', 'تدلّي الوجه أو ضعف الذراع أو صعوبة الكلام (FAST)'),
      Tx('Sudden vision, balance or confusion problems', 'مشكلات مفاجئة في الرؤية أو الاتزان أو تشوش'),
    ],
    self: Guide(Tx('If you notice FAST signs in yourself', 'لو لاحظت علامات FAST على نفسك'), [
      Tx('Call a crewmate and mission medical support immediately.', 'نادِ زميلًا واتصل بالدعم الطبي فورًا.'),
      Tx('Note the exact time the symptoms started.', 'دوّن الوقت الدقيق لبدء الأعراض.'),
      Tx('Stay still and secure yourself. Do not try to eat or drink.', 'ابقَ ساكنًا وثبّت نفسك. لا تحاول الأكل أو الشرب.'),
    ]),
    helper: Guide(Tx('If a crewmate shows FAST signs', 'لو زميل تظهر عليه علامات FAST'), [
      Tx('Face: ask them to smile. Arms: ask them to raise both. Speech: ask them to repeat a simple sentence.', 'الوجه: اطلب منه أن يبتسم. الذراعان: اطلب رفعهما. الكلام: اطلب تكرار جملة بسيطة.'),
      Tx('If any sign is present, treat it as an emergency: call mission medical support now.', 'لو ظهرت أي علامة فاعتبرها طارئة واتصل بالدعم الطبي الآن.'),
      Tx('Record the time symptoms began and keep them safe and still.', 'سجّل وقت بدء الأعراض وأبقِه آمنًا وساكنًا.'),
    ]),
    place: {
      Place.cabin: Tx('In the cabin: restrain the person safely and keep communication open with mission control.', 'داخل المركبة: ثبّت الشخص بأمان وأبقِ الاتصال مفتوحًا مع مركز التحكم.'),
      Place.eva: Tx('On EVA: do not tell an impaired astronaut to move. Alert the crew and mission control and follow the approved EVA contingency procedure.', 'في المهمة الخارجية: لا تطلب من رائد غير قادر أن يتحرك. أبلغ الطاقم ومركز التحكم واتبع إجراء الطوارئ المعتمد.'),
      Place.ground: Tx('On the ground: call emergency services immediately.', 'على الأرض: اتصل بالإسعاف فورًا.'),
    },
    avoid: [
      Tx('Do not give food, drink or medicine.', 'لا تعطِ طعامًا أو شرابًا أو دواءً.'),
      Tx('Do not wait to see if it improves.', 'لا تنتظر لترى هل يتحسن.'),
    ],
    escalate: [Tx('Any FAST sign: emergency now.', 'أي علامة من FAST: طوارئ فورًا.')],
    space: Tx('Imaging and treatment decisions belong to mission medical support.', 'قرارات التصوير والعلاج من اختصاص الدعم الطبي للمهمة.'),
    sources: [_aha, _nasaCare],
  ),
  Protocol(
    kind: EmergencyKind.dehydration,
    title: Tx('Dehydration or electrolyte concern', 'جفاف أو اضطراب أملاح'),
    possibility: Tx('Possible dehydration or electrolyte concern. These readings cannot confirm it.', 'احتمال جفاف أو اضطراب أملاح. القراءات لا تؤكد ذلك.'),
    criteria: [
      Tx('Unusual fatigue, dizziness, thirst, little urine, abnormal heart rate', 'إرهاق غير معتاد أو دوخة أو عطش أو قلة تبول أو نبض غير طبيعي'),
    ],
    self: Guide(Tx('If you feel dehydrated or drained', 'لو حاسس بجفاف أو إنهاك'), [
      Tx('Rest and stop heavy activity.', 'استرح وأوقف الأنشطة الشاقة.'),
      Tx('Collect information: recent fluid and food intake, sweating, vomiting or diarrhea, and urine output.', 'اجمع المعلومات: ما شربته وأكلته مؤخرًا والتعرق والقيء أو الإسهال وكمية البول.'),
      Tx('Share it with mission medical support and follow their advice.', 'شاركها مع الدعم الطبي واتبع نصيحتهم.'),
    ]),
    helper: Guide(Tx('If a crewmate may be dehydrated', 'لو زميل قد يكون عنده جفاف'), [
      Tx('Help them rest and check they are alert and responding normally.', 'ساعده على الراحة وتأكد أنه متيقظ ويستجيب طبيعيًا.'),
      Tx('Gather the same information and contact mission medical support.', 'اجمع نفس المعلومات واتصل بالدعم الطبي.'),
    ]),
    place: {
      Place.cabin: Tx('In the cabin: follow the mission hydration plan and the medical officer’s advice.', 'داخل المركبة: اتبع خطة الترطيب للمهمة ونصيحة الطبيب.'),
      Place.eva: Tx('On EVA: report symptoms and follow the approved EVA procedure; do not leave your task path on your own.', 'في المهمة الخارجية: أبلغ بالأعراض واتبع إجراء المهمة المعتمد ولا تغيّر مسارك من تلقاء نفسك.'),
      Place.ground: Tx('On the ground: rest in a cool place and seek medical advice if symptoms continue.', 'على الأرض: استرح في مكان بارد واطلب مشورة طبية لو استمرت الأعراض.'),
    },
    avoid: [
      Tx('Do not take electrolyte supplements or medicine without an approved protocol.', 'لا تتناول مكملات أملاح أو دواءً دون بروتوكول معتمد.'),
    ],
    escalate: [Tx('Confusion, fainting, or a very fast heart rate.', 'تشوش أو إغماء أو نبض سريع جدًا.')],
    space: Tx('Fluid and electrolyte management in flight follows mission medical protocols.', 'إدارة السوائل والأملاح في الرحلة تتبع بروتوكولات المهمة الطبية.'),
    sources: [_nasaCare, _nasaOps],
    severity: 1,
  ),
  Protocol(
    kind: EmergencyKind.heat,
    title: Tx('Heat stress or hyperthermia', 'إجهاد حراري أو ارتفاع حرارة الجسم'),
    possibility: Tx('Possible heat stress. Confusion with high temperature may be heat stroke, which is an emergency.', 'احتمال إجهاد حراري. التشوش مع الحرارة العالية قد يكون ضربة شمس وهي طارئة.'),
    criteria: [
      Tx('High body temperature, heavy sweating, weakness, dizziness', 'حرارة مرتفعة وتعرق شديد وضعف ودوخة'),
      Tx('Confusion', 'تشوش'),
    ],
    self: Guide(Tx('If you are overheating', 'لو بتحس بسخونة زائدة'), [
      Tx('Stop activity and tell a crewmate.', 'أوقف النشاط وأخبر زميلًا.'),
      Tx('Cool down: reduce heat load and loosen or remove extra clothing where it is safe to do so.', 'برّد جسمك: قلّل مصدر الحرارة وأرخِ أو اخلع الملابس الزائدة إن كان آمنًا.'),
      _contactMcc,
    ]),
    helper: Guide(Tx('If a crewmate shows heat stress', 'لو زميل تظهر عليه علامات إجهاد حراري'), [
      Tx('Move them to the coolest safe area and loosen clothing.', 'انقله لأبرد مكان آمن وأرخِ ملابسه.'),
      Tx('Cool with a damp cloth and airflow, and check responsiveness and breathing.', 'برّده بقطعة قماش مبللة وتيار هواء وتحقق من الاستجابة والتنفس.'),
      Tx('If confused or unresponsive, treat as heat stroke: emergency now, call mission medical support.', 'لو مشوش أو غير مستجيب فاعتبرها ضربة شمس: طوارئ الآن واتصل بالدعم الطبي.'),
    ]),
    place: {
      Place.cabin: Tx('In the cabin: use the cabin cooling and airflow controls as the approved procedure allows.', 'داخل المركبة: استخدم التبريد وتيار الهواء كما يسمح الإجراء المعتمد.'),
      Place.eva: Tx('On EVA: use the suit cooling controls and report to the crew and mission control. Follow the approved EVA procedure for ending the task.', 'في المهمة الخارجية: استخدم تحكم تبريد البدلة وأبلغ الطاقم ومركز التحكم، واتبع إجراء إنهاء المهمة المعتمد.'),
      Place.ground: Tx('On the ground: move to shade or a cool room and cool the skin; call emergency services for heat stroke.', 'على الأرض: انتقل للظل أو غرفة باردة وبرّد الجلد، واتصل بالإسعاف عند ضربة الشمس.'),
    },
    avoid: [
      Tx('Do not give drinks to someone who is confused or drowsy.', 'لا تعطِ مشروبات لمن هو مشوش أو ناعس.'),
    ],
    escalate: [Tx('Confusion, fainting or a rising temperature despite cooling.', 'تشوش أو إغماء أو حرارة ترتفع رغم التبريد.')],
    space: Tx('Spaceflight cooling depends on suit and cabin systems; follow the approved procedure.', 'التبريد في الفضاء يعتمد على أنظمة البدلة والمقصورة، فاتبع الإجراء المعتمد.'),
    sources: [_aha, _nasaCare],
    severity: 2,
  ),
  Protocol(
    kind: EmergencyKind.radiation,
    title: Tx('Radiation event', 'حدث إشعاعي'),
    possibility: Tx('Possible radiation event. Dose readings alone cannot diagnose radiation sickness.', 'احتمال حدث إشعاعي. قراءات الجرعة وحدها لا تشخص مرض الإشعاع.'),
    criteria: [
      Tx('Dose rate far above the quiet level, or a solar particle event warning', 'معدل جرعة أعلى بكثير من المستوى الهادئ أو تحذير من عاصفة جسيمات شمسية'),
    ],
    self: Guide(Tx('If a radiation alert is active', 'لو إنذار الإشعاع مفعّل'), [
      Tx('Go to the designated radiation shelter area and follow the spacecraft shelter procedure.', 'اذهب لمنطقة الحماية الإشعاعية المخصصة واتبع إجراء الملجأ في المركبة.'),
      Tx('Record the dose rate and the time. Dose rate (µGy/h) and accumulated dose (µGy) are different numbers.', 'سجّل معدل الجرعة والوقت. معدل الجرعة (µGy/h) والجرعة المتراكمة (µGy) رقمان مختلفان.'),
      Tx('Notify mission control and wait for their instructions.', 'أبلغ مركز التحكم وانتظر تعليماتهم.'),
    ]),
    helper: Guide(Tx('If a crewmate is exposed', 'لو زميل تعرض للإشعاع'), [
      Tx('Help them reach the shelter area if they are able.', 'ساعده للوصول لمنطقة الحماية إن كان قادرًا.'),
      Tx('Record exposure information and the time, and notify mission control.', 'سجّل معلومات التعرض والوقت وأبلغ مركز التحكم.'),
      Tx('Arrange medical evaluation and monitoring as mission control directs.', 'رتّب التقييم والمتابعة الطبية كما يوجّه مركز التحكم.'),
    ]),
    place: {
      Place.cabin: Tx('In the cabin: use the shelter area and follow the approved procedure.', 'داخل المركبة: استخدم منطقة الحماية واتبع الإجراء المعتمد.'),
      Place.eva: Tx('On EVA: end or suspend the task as mission control directs, and follow the approved EVA contingency procedure. No route is invented.', 'في المهمة الخارجية: أنهِ أو أوقف المهمة كما يوجّه مركز التحكم واتبع إجراء الطوارئ المعتمد. لا يتم اختراع مسار.'),
      Place.ground: Tx('Radiation shelter does not apply on the ground. This is a spaceflight scenario.', 'الملجأ الإشعاعي لا ينطبق على الأرض. هذا سيناريو خاص بالفضاء.'),
    },
    avoid: [Tx('Do not diagnose radiation sickness from dose numbers.', 'لا تشخّص مرض الإشعاع من أرقام الجرعة.')],
    escalate: [Tx('A solar particle event warning or a sharp rise in dose rate.', 'تحذير من عاصفة جسيمات شمسية أو ارتفاع حاد في معدل الجرعة.')],
    space: Tx('Shelter procedures are mission-specific. Use the approved mission procedure.', 'إجراءات الملجأ خاصة بكل مهمة. استخدم الإجراء المعتمد.'),
    sources: [_nasaStd, _nasaOps],
  ),
  Protocol(
    kind: EmergencyKind.allergy,
    title: Tx('Severe allergic reaction', 'تفاعل تحسسي شديد'),
    possibility: Tx('Possible severe allergic reaction (anaphylaxis). Not a diagnosis.', 'احتمال تفاعل تحسسي شديد. وليس تشخيصًا.'),
    criteria: [
      Tx('Face or throat swelling, trouble breathing, widespread hives, dizziness or collapse', 'تورم الوجه أو الحلق أو صعوبة تنفس أو طفح واسع أو دوخة أو انهيار'),
    ],
    self: Guide(Tx('If you think you are having a severe allergic reaction', 'لو حاسس بتفاعل تحسسي شديد'), [
      Tx('Call for help now and alert mission medical support.', 'اطلب المساعدة الآن وأبلغ الدعم الطبي.'),
      Tx('Stop contact with the suspected trigger if you can.', 'ابتعد عن المسبب المشتبه فيه إن أمكن.'),
      Tx('Use an emergency medicine only if the medical officer directs it under an approved protocol.', 'استخدم دواء الطوارئ فقط لو وجّه الطبيب بذلك وفق بروتوكول معتمد.'),
    ]),
    helper: Guide(Tx('If a crewmate has a severe allergic reaction', 'لو زميل عنده تفاعل تحسسي شديد'), [
      Tx('Call mission medical support now and stay with them.', 'اتصل بالدعم الطبي الآن وابقَ معه.'),
      Tx('Help with their emergency medicine only as the medical officer directs under an approved protocol.', 'ساعده في دواء الطوارئ فقط كما يوجّه الطبيب وفق بروتوكول معتمد.'),
      Tx('Watch breathing and responsiveness. If not breathing normally, start CPR per the approved procedure.', 'راقب التنفس والاستجابة. لو لا يتنفس بشكل طبيعي فابدأ الإنعاش بالإجراء المعتمد.'),
    ]),
    place: {
      Place.cabin: Tx('In the cabin: restrain the person and bring the medical kit to them.', 'داخل المركبة: ثبّت الشخص وأحضر الحقيبة الطبية إليه.'),
      Place.eva: Tx('On EVA: alert the crew and mission control and follow the approved EVA contingency procedure.', 'في المهمة الخارجية: أبلغ الطاقم ومركز التحكم واتبع إجراء الطوارئ المعتمد.'),
      Place.ground: Tx('On the ground: call emergency services immediately. Lie down with legs raised unless breathing is difficult; then sit up.', 'على الأرض: اتصل بالإسعاف فورًا. يستلقي مع رفع الساقين إلا لو التنفس صعب فيجلس معتدلًا.'),
    },
    avoid: [Tx('Do not give medicine without authorization.', 'لا تعطِ دواءً دون تصريح.')],
    escalate: [Tx('Any throat swelling or breathing trouble: emergency now.', 'أي تورم بالحلق أو صعوبة تنفس: طوارئ فورًا.')],
    space: Tx('Spaceflight treatment follows mission medical protocols.', 'العلاج في الفضاء يتبع بروتوكولات المهمة الطبية.'),
    sources: [_aha, _nasaCare],
  ),
  Protocol(
    kind: EmergencyKind.psychological,
    title: Tx('Psychological crisis', 'أزمة نفسية'),
    possibility: Tx('Possible psychological crisis. This is not a diagnosis. Laila is not a therapist.', 'احتمال أزمة نفسية. وليس تشخيصًا. ليلى ليست معالجة نفسية.'),
    criteria: [
      Tx('Severe anxiety or panic, severe distress, thoughts of self-harm or suicide', 'قلق أو ذعر شديد أو ضيق شديد أو أفكار إيذاء النفس أو الانتحار'),
    ],
    self: Guide(Tx('If you are in distress', 'لو إنت في ضيق شديد'), [
      Tx('You are not alone. Tell a crewmate now, or press "I need a person now".', 'إنت مش لوحدك. أخبر زميلًا الآن أو اضغط "I need a person now".'),
      Tx('Slow your breathing: in for 4, hold for 4, out for 6.', 'هدّئ تنفسك: شهيق 4 وحبس 4 وزفير 6.'),
      Tx('Contact the mission medical officer or mission support. Ask for a person to talk to.', 'تواصل مع الطبيب المسؤول أو دعم المهمة. اطلب شخصًا يتحدث معك.'),
    ]),
    helper: Guide(Tx('If a crewmate is in crisis', 'لو زميل في أزمة'), [
      Tx('Stay with them and listen calmly. Do not leave them alone.', 'ابقَ معه واستمع بهدوء. لا تتركه وحده.'),
      Tx('If they mention self-harm, take the question seriously and ask directly. Remove anything that could be used to hurt themselves.', 'لو ذكر إيذاء النفس فخذ الأمر بجدية واسأله مباشرة. أبعد أي شيء قد يؤذي به نفسه.'),
      Tx('Contact the mission medical officer and mission support urgently.', 'تواصل بشكل عاجل مع الطبيب المسؤول ودعم المهمة.'),
    ]),
    place: {
      Place.cabin: Tx('In the cabin: stay together in a safe, quiet area and keep a line to mission support open.', 'داخل المركبة: ابقيا معًا في مكان آمن وهادئ وأبقِ خطًا مفتوحًا مع دعم المهمة.'),
      Place.eva: Tx('On EVA: tell the crew and mission control; follow the approved EVA contingency procedure for ending the task.', 'في المهمة الخارجية: أبلغ الطاقم ومركز التحكم واتبع إجراء إنهاء المهمة المعتمد.'),
      Place.ground: Tx('On the ground: stay with the person and call your local emergency number or a crisis line.', 'على الأرض: ابقَ مع الشخص واتصل برقم الطوارئ المحلي أو خط أزمات.'),
    },
    avoid: [
      Tx('Do not leave the person alone.', 'لا تترك الشخص وحده.'),
      Tx('Do not rely on the app or Laila as the only support.', 'لا تعتمد على التطبيق أو ليلى كدعم وحيد.'),
    ],
    escalate: [Tx('Any thought of self-harm: urgent human help now.', 'أي فكرة لإيذاء النفس: مساعدة بشرية عاجلة الآن.')],
    space: Tx('Mission medical officer and mission support lead the response.', 'الطبيب المسؤول ودعم المهمة يقودان الاستجابة.'),
    sources: [_nasaCare, _nasaOps],
  ),
];

Protocol protocolFor(EmergencyKind k) => kProtocols.firstWhere((p) => p.kind == k);
