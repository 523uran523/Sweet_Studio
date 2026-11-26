/// Чистые правила расчёта начислений.
///
/// Зачем отдельный файл: одна формула обязана давать один результат и в
/// миграции v26 (бэкфилл предварительных ведомостей), и в закрытии периода,
/// и в экспорте PDF. Деньги — копейки, `double` — только проценты,
/// округление — на строке начисления.
library;

/// Почасовая/окладная строка: минуты × ставка / 60.
int hourlyAccrualCents(int minutes, int rateCents) =>
    (minutes * rateCents / 60).round();

/// Сдельная строка: количество завершённых заказов × ставка.
int pieceAccrualCents(int doneJobs, int rateCents) => doneJobs * rateCents;

/// Процентная строка: цена заказа × процент / 100.
int percentAccrualCents(int priceCents, double percent) =>
    (priceCents * percent / 100).round();

/// Итог к выплате по ведомости: начисленное + премии − штрафы − авансы −
/// выплаты.
int netPayCents({
  required int accrued,
  required int bonuses,
  required int penalties,
  required int advances,
  required int payouts,
}) => accrued + bonuses - penalties - advances - payouts;

/// Полуоткрытая граница конца периода: `[начало, конец)`.
///
/// Хранимый `end_at` — последний момент периода (23:59:59.999); сдвиг на
/// 1 мс даёт ту же принадлежность записей, что и прежнее включённое
/// сравнение, и при этом соседние периоды не перекрываются на границе.
DateTime periodEndExclusive(DateTime end) =>
    end.add(const Duration(milliseconds: 1));
