enum AppThemeKind { berryCream, vanillaPistachio, porcelain, darkChocolate }

enum InventoryKind { raw, semi, finished, packaging }

enum StockLotStatus { active, quarantine, expired, depleted }

enum MovementKind {
  receipt,
  issue,
  adjustment,
  productionIn,
  productionOut,
  sale,
}

enum PurchaseStatus { planned, ordered, received, cancelled }

enum ProductionStatus { planned, completed, reversed }

enum OrderStatus {
  lead,
  negotiation,
  confirmed,
  inProgress,
  ready,
  delivered,
  closed,
  cancelled,
}

enum WorkItemType {
  order,
  production,
  task,
  purchase,
  finance,
  quality,
  promo,
}

enum WorkPriority { low, normal, high }

enum WorkStage { queue, inProgress, done }

enum WorkRecurrence { none, daily, weekly, biweekly, monthly }

enum AccountKind { cash, card, bank }

enum TransactionKind { income, expense, transfer, reversal }

class StudioProfile {
  const StudioProfile({
    this.studioName = 'Моя кондитерская',
    this.slogan = 'Авторские десерты на заказ',
    this.currencySymbol = '₽',
    this.themeIndex = 0,
    this.hiddenModules = const [],
    this.isDemoMode = false,
    this.onboardingCompleted = false,
    this.lastBackupAt,
    this.notifyOrders = true,
    this.notifyTasks = true,
    this.notifyStock = true,
    this.notifyExpiry = true,
    this.localNotificationsEnabled = false,
  });

  final String studioName;
  final String slogan;
  final String currencySymbol;
  final int themeIndex;
  final List<String> hiddenModules;
  final bool isDemoMode;
  final bool onboardingCompleted;
  final String? lastBackupAt;
  final bool notifyOrders;
  final bool notifyTasks;
  final bool notifyStock;
  final bool notifyExpiry;
  final bool localNotificationsEnabled;

  StudioProfile copyWith({
    String? studioName,
    String? slogan,
    String? currencySymbol,
    int? themeIndex,
    List<String>? hiddenModules,
    bool? isDemoMode,
    bool? onboardingCompleted,
    String? lastBackupAt,
    bool? notifyOrders,
    bool? notifyTasks,
    bool? notifyStock,
    bool? notifyExpiry,
    bool? localNotificationsEnabled,
  }) {
    return StudioProfile(
      studioName: studioName ?? this.studioName,
      slogan: slogan ?? this.slogan,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      themeIndex: themeIndex ?? this.themeIndex,
      hiddenModules: hiddenModules ?? this.hiddenModules,
      isDemoMode: isDemoMode ?? this.isDemoMode,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      notifyOrders: notifyOrders ?? this.notifyOrders,
      notifyTasks: notifyTasks ?? this.notifyTasks,
      notifyStock: notifyStock ?? this.notifyStock,
      notifyExpiry: notifyExpiry ?? this.notifyExpiry,
      localNotificationsEnabled:
          localNotificationsEnabled ?? this.localNotificationsEnabled,
    );
  }
}

class RecipeIngredientLine {
  const RecipeIngredientLine({
    this.itemId,
    this.subRecipeId,
    required this.name,
    required this.qty,
    required this.unit,
    this.lossPercent = 0,
    required this.priceCents,
    required this.priceUnit,
    this.isPackaging = false,
  });

  final String? itemId;
  final String? subRecipeId;
  final String name;
  final double qty;
  final String unit;
  final double lossPercent;
  final int priceCents;
  final String priceUnit;
  final bool isPackaging;

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'subRecipeId': subRecipeId,
        'name': name,
        'qty': qty,
        'unit': unit,
        'lossPercent': lossPercent,
        'priceCents': priceCents,
        'priceUnit': priceUnit,
        'isPackaging': isPackaging,
      };

  factory RecipeIngredientLine.fromJson(Map<String, dynamic> json) =>
      RecipeIngredientLine(
        itemId: json['itemId'] as String?,
        subRecipeId: json['subRecipeId'] as String?,
        name: (json['name'] ?? '') as String,
        qty: ((json['qty'] ?? 0) as num).toDouble(),
        unit: (json['unit'] ?? 'г') as String,
        lossPercent: ((json['lossPercent'] ?? 0) as num).toDouble(),
        priceCents: ((json['priceCents'] ?? 0) as num).round(),
        priceUnit: (json['priceUnit'] ?? 'за кг') as String,
        isPackaging: json['isPackaging'] == true,
      );
}

class RecipePackVariant {
  const RecipePackVariant({
    required this.id,
    required this.label,
    required this.qtyOrGrams,
    required this.mode,
    this.packagingCents = 0,
    this.priceCents,
  });

  final String id;
  final String label;
  final double qtyOrGrams;
  final String mode; // 'grams' | 'pieces'
  final int packagingCents;
  final int? priceCents;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'qtyOrGrams': qtyOrGrams,
        'mode': mode,
        'packagingCents': packagingCents,
        'priceCents': priceCents,
      };

  factory RecipePackVariant.fromJson(Map<String, dynamic> json) =>
      RecipePackVariant(
        id: (json['id'] ?? '') as String,
        label: (json['label'] ?? '') as String,
        qtyOrGrams: ((json['qtyOrGrams'] ?? 0) as num).toDouble(),
        mode: (json['mode'] ?? 'grams') as String,
        packagingCents: ((json['packagingCents'] ?? 0) as num).round(),
        priceCents: json['priceCents'] != null
            ? (json['priceCents'] as num).round()
            : null,
      );
}

class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.category,
    this.version = 1,
    this.status = 'approved',
    required this.yieldGrams,
    this.grossGrams,
    this.yieldPortions = 1,
    this.formSize,
    this.photoPath,
    this.ingredients = const [],
    this.packVariants = const [],
    this.steps = const [],
    this.allergens = const [],
    this.laborHours = 1.5,
    this.laborRateCents = 55000,
    this.packagingCents = 0,
    this.overheadPercent = 10,
    this.marginPercent = 45,
    required this.costCents,
    required this.recommendedPriceCents,
    this.shelfLifeHours = 72,
    this.storageCondition,
    this.favorite = false,
    this.updatedAt = '',
  });

  final String id;
  final String title;
  final String category;
  final int version;
  final String status;
  final double yieldGrams;
  final double? grossGrams;
  final int yieldPortions;
  final String? formSize;
  final String? photoPath; // relative filename in media/
  final List<RecipeIngredientLine> ingredients;
  final List<RecipePackVariant> packVariants;
  final List<String> steps;
  final List<String> allergens;
  final double laborHours;
  final int laborRateCents;
  final int packagingCents;
  final double overheadPercent;
  final double marginPercent;
  final int costCents;
  final int recommendedPriceCents;
  final int shelfLifeHours;
  final String? storageCondition;
  final bool favorite;
  final String updatedAt;

  Recipe copyWith({
    String? title,
    String? category,
    int? version,
    String? status,
    double? yieldGrams,
    double? grossGrams,
    int? yieldPortions,
    String? formSize,
    String? photoPath,
    bool clearPhoto = false,
    List<RecipeIngredientLine>? ingredients,
    List<RecipePackVariant>? packVariants,
    List<String>? steps,
    List<String>? allergens,
    double? laborHours,
    int? laborRateCents,
    int? packagingCents,
    double? overheadPercent,
    double? marginPercent,
    int? costCents,
    int? recommendedPriceCents,
    int? shelfLifeHours,
    String? storageCondition,
    bool? favorite,
    String? updatedAt,
  }) {
    return Recipe(
      id: id,
      title: title ?? this.title,
      category: category ?? this.category,
      version: version ?? this.version,
      status: status ?? this.status,
      yieldGrams: yieldGrams ?? this.yieldGrams,
      grossGrams: grossGrams ?? this.grossGrams,
      yieldPortions: yieldPortions ?? this.yieldPortions,
      formSize: formSize ?? this.formSize,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      ingredients: ingredients ?? this.ingredients,
      packVariants: packVariants ?? this.packVariants,
      steps: steps ?? this.steps,
      allergens: allergens ?? this.allergens,
      laborHours: laborHours ?? this.laborHours,
      laborRateCents: laborRateCents ?? this.laborRateCents,
      packagingCents: packagingCents ?? this.packagingCents,
      overheadPercent: overheadPercent ?? this.overheadPercent,
      marginPercent: marginPercent ?? this.marginPercent,
      costCents: costCents ?? this.costCents,
      recommendedPriceCents:
          recommendedPriceCents ?? this.recommendedPriceCents,
      shelfLifeHours: shelfLifeHours ?? this.shelfLifeHours,
      storageCondition: storageCondition ?? this.storageCondition,
      favorite: favorite ?? this.favorite,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.kind,
    this.category,
    required this.unit,
    required this.qtyOnHand,
    this.minQty = 0,
    required this.avgCostCents,
    this.density,
  });

  final String id;
  final String name;
  final InventoryKind kind;
  final String? category;
  final String unit;
  final double qtyOnHand;
  final double minQty;
  final int avgCostCents;
  final double? density;
}

class StockLot {
  const StockLot({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.lotCode,
    required this.unit,
    required this.initialQty,
    required this.remainingQty,
    required this.unitCostCents,
    this.expiresAt,
    this.status = StockLotStatus.active,
    this.createdAt = '',
  });

  final String id;
  final String itemId;
  final String itemName;
  final String lotCode;
  final String unit;
  final double initialQty;
  final double remainingQty;
  final int unitCostCents;
  final String? expiresAt;
  final StockLotStatus status;
  final String createdAt;
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.kind,
    required this.itemId,
    required this.itemName,
    this.lotId,
    required this.qty,
    required this.unit,
    required this.totalCents,
    this.reason,
    required this.occurredAt,
  });

  final String id;
  final MovementKind kind;
  final String itemId;
  final String itemName;
  final String? lotId;
  final double qty;
  final String unit;
  final int totalCents;
  final String? reason;
  final String occurredAt;
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.contactName,
    this.phone,
    this.category,
    this.debtCents = 0,
  });

  final String id;
  final String name;
  final String? contactName;
  final String? phone;
  final String? category;
  final int debtCents;
}

class Purchase {
  const Purchase({
    required this.id,
    this.supplierId,
    required this.supplierName,
    this.itemId,
    required this.itemName,
    required this.qty,
    required this.unit,
    required this.priceCents,
    this.deliveryCents = 0,
    this.expectedDate,
    this.expiresAt,
    this.status = PurchaseStatus.ordered,
  });

  final String id;
  final String? supplierId;
  final String supplierName;
  final String? itemId;
  final String itemName;
  final double qty;
  final String unit;
  final int priceCents;
  final int deliveryCents;
  final String? expectedDate;
  final String? expiresAt;
  final PurchaseStatus status;
}

class ProductionRun {
  const ProductionRun({
    required this.id,
    this.recipeId,
    required this.recipeTitle,
    required this.plannedGrams,
    this.actualGrams = 0,
    this.totalCostCents = 0,
    this.outputLotId,
    this.status = ProductionStatus.completed,
    required this.createdAt,
  });

  final String id;
  final String? recipeId;
  final String recipeTitle;
  final double plannedGrams;
  final double actualGrams;
  final int totalCostCents;
  final String? outputLotId;
  final ProductionStatus status;
  final String createdAt;
}

class Client {
  const Client({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.preferences,
    this.allergens,
    this.depositCents = 0,
    this.favorite = false,
  });

  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? preferences;
  final String? allergens;
  final int depositCents;
  final bool favorite;
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.recipeId,
    required this.recipeTitle,
    required this.qty,
    required this.weightGrams,
    required this.priceCents,
    required this.costCents,
  });

  final String id;
  final String recipeId;
  final String recipeTitle;
  final int qty;
  final double weightGrams;
  final int priceCents; // unit price cents
  final int costCents; // unit cost cents

  Map<String, dynamic> toJson() => {
        'id': id,
        'recipeId': recipeId,
        'recipeTitle': recipeTitle,
        'qty': qty,
        'weightGrams': weightGrams,
        'priceCents': priceCents,
        'costCents': costCents,
      };

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: (json['id'] ?? '') as String,
        recipeId: (json['recipeId'] ?? '') as String,
        recipeTitle: (json['recipeTitle'] ?? '') as String,
        qty: ((json['qty'] ?? 1) as num).round().clamp(1, 10000),
        weightGrams: ((json['weightGrams'] ?? 0) as num).toDouble(),
        priceCents: ((json['priceCents'] ?? 0) as num).round(),
        costCents: ((json['costCents'] ?? 0) as num).round(),
      );
}

class Order {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.title,
    this.clientId,
    required this.clientName,
    this.items = const [],
    this.recipeId,
    this.recipeTitle,
    this.weightGrams = 0,
    required this.priceCents,
    required this.costCents,
    this.prepaymentCents = 0,
    this.paidCents = 0,
    this.discountCents = 0,
    this.status = OrderStatus.confirmed,
    this.dueDate,
    this.deliveryAddress,
    this.wishes,
    this.allergens,
    this.stockDeducted = false,
    this.favorite = false,
    required this.createdAt,
  });

  final String id;
  final String orderNumber;
  final String title;
  final String? clientId;
  final String clientName;
  final List<OrderItem> items;
  final String? recipeId;
  final String? recipeTitle;
  final double weightGrams;
  final int priceCents;
  final int costCents;
  final int prepaymentCents;
  final int paidCents;
  final int discountCents;
  final OrderStatus status;
  final String? dueDate;
  final String? deliveryAddress;
  final String? wishes;
  final String? allergens;
  final bool stockDeducted;
  final bool favorite;
  final String createdAt;

  int get balanceDueCents =>
      (priceCents - paidCents) > 0 ? (priceCents - paidCents) : 0;
}

class WorkItem {
  const WorkItem({
    required this.id,
    required this.type,
    this.sourceId,
    required this.title,
    this.dueDate,
    this.priority = WorkPriority.normal,
    this.stage = WorkStage.queue,
    this.tags = const [],
    this.recurrence = WorkRecurrence.none,
    this.seriesId,
    this.occurrenceIndex,
  });

  final String id;
  final WorkItemType type;
  final String? sourceId;
  final String title;
  final String? dueDate;
  final WorkPriority priority;
  final WorkStage stage;
  final List<String> tags;
  final WorkRecurrence recurrence;
  final String? seriesId;
  final int? occurrenceIndex;
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    required this.balanceCents,
  });

  final String id;
  final String name;
  final AccountKind kind;
  final int balanceCents;
}

class MoneyTransaction {
  const MoneyTransaction({
    required this.id,
    required this.kind,
    required this.category,
    required this.amountCents,
    required this.accountId,
    required this.accountName,
    this.orderId,
    this.reversesId,
    this.note,
    required this.occurredAt,
  });

  final String id;
  final TransactionKind kind;
  final String category;
  final int amountCents;
  final String accountId;
  final String accountName;
  final String? orderId;
  final String? reversesId;
  final String? note;
  final String occurredAt;
}

class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.date,
    required this.minutes,
    this.note,
  });

  final String id;
  final String date;
  final int minutes;
  final String? note;
}

const Map<OrderStatus, String> kOrderStatusLabelsRu = {
  OrderStatus.lead: 'Заявка',
  OrderStatus.negotiation: 'Согласование',
  OrderStatus.confirmed: 'Подтверждён',
  OrderStatus.inProgress: 'В работе',
  OrderStatus.ready: 'Готов',
  OrderStatus.delivered: 'Выдан',
  OrderStatus.closed: 'Закрыт',
  OrderStatus.cancelled: 'Отменён',
};

const Map<InventoryKind, String> kInventoryKindLabelsRu = {
  InventoryKind.raw: 'Сырьё',
  InventoryKind.semi: 'Полуфабрикаты',
  InventoryKind.finished: 'Готовые изделия',
  InventoryKind.packaging: 'Упаковка и декор',
};

const Map<WorkStage, String> kWorkStageLabelsRu = {
  WorkStage.queue: 'Очередь',
  WorkStage.inProgress: 'В работе',
  WorkStage.done: 'Готово',
};
