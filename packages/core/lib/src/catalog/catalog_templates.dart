/// Preset product template for smart catalog suggestion.
class CatalogTemplateItem {
  const CatalogTemplateItem({
    required this.name,
    required this.priceRupees,
    required this.unit,
    required this.category,
    required this.description,
    this.isSelected = true,
  });

  final String name;
  final double priceRupees;
  final String unit;
  final String category;
  final String description;
  final bool isSelected;

  CatalogTemplateItem copyWith({
    String? name,
    double? priceRupees,
    String? unit,
    String? category,
    String? description,
    bool? isSelected,
  }) {
    return CatalogTemplateItem(
      name: name ?? this.name,
      priceRupees: priceRupees ?? this.priceRupees,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      description: description ?? this.description,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

/// Curated smart catalog suggestion presets for different business types.
abstract final class CatalogTemplates {
  static const kiranaCategory = 'Kirana & Grocery';
  static const medicalCategory = 'Medical & Pharmacy';
  static const bakeryCategory = 'Bakery & Cake Shop';
  static const restaurantCategory = 'Restaurant & Food';
  static const freshProduceCategory = 'Fruits & Vegetables';
  static const stationeryCategory = 'Stationery & Printing';

  static const categories = [
    kiranaCategory,
    medicalCategory,
    bakeryCategory,
    restaurantCategory,
    freshProduceCategory,
    stationeryCategory,
  ];

  static List<CatalogTemplateItem> getSuggestionsForCategory(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('kirana') || lower.contains('grocery') || lower.contains('general')) {
      return kiranaSuggestions;
    } else if (lower.contains('medical') || lower.contains('pharmacy') || lower.contains('chemist')) {
      return medicalSuggestions;
    } else if (lower.contains('cake') || lower.contains('bakery') || lower.contains('pastry')) {
      return bakerySuggestions;
    } else if (lower.contains('restaurant') || lower.contains('food') || lower.contains('snack') || lower.contains('cafe')) {
      return restaurantSuggestions;
    } else if (lower.contains('fruit') || lower.contains('vegetable')) {
      return freshProduceSuggestions;
    } else {
      return stationerySuggestions;
    }
  }

  static const List<CatalogTemplateItem> kiranaSuggestions = [
    CatalogTemplateItem(
      name: 'Amul Taaza Homogenised Toned Milk',
      priceRupees: 27,
      unit: '500ml',
      category: 'Dairy',
      description: 'Pasteurized toned milk, rich in calcium and vitamins.',
    ),
    CatalogTemplateItem(
      name: 'Aashirvaad Shudh Chakki Atta',
      priceRupees: 245,
      unit: '5 kg',
      category: 'Flours & Grains',
      description: '100% whole wheat flour, naturally rich in dietary fibre.',
    ),
    CatalogTemplateItem(
      name: 'Fortune Sunlite Refined Sunflower Oil',
      priceRupees: 145,
      unit: '1 Litre',
      category: 'Edible Oils',
      description: 'Light and healthy refined sunflower cooking oil.',
    ),
    CatalogTemplateItem(
      name: 'Tata Salt Vaccum Evaporated Iodized Salt',
      priceRupees: 28,
      unit: '1 kg',
      category: 'Spices & Seasoning',
      description: 'India’s trusted vacuum evaporated iodized salt.',
    ),
    CatalogTemplateItem(
      name: 'Maggi 2-Minute Masala Instant Noodles',
      priceRupees: 14,
      unit: '70g',
      category: 'Instant Food',
      description: 'Classic favourite masala noodles with tastemaker.',
    ),
    CatalogTemplateItem(
      name: 'Madhur Pure & Hygienic Sugar (Cheeni)',
      priceRupees: 48,
      unit: '1 kg',
      category: 'Staples',
      description: 'Sulphur-free, pure crystal white sugar.',
    ),
    CatalogTemplateItem(
      name: 'Tata Sampann Unpolished Toor Dal',
      priceRupees: 165,
      unit: '1 kg',
      category: 'Pulses & Dal',
      description: 'High protein unpolished arhar/toor dal.',
    ),
    CatalogTemplateItem(
      name: 'Britannia 100% Whole Wheat Bread',
      priceRupees: 45,
      unit: '400g',
      category: 'Bakery',
      description: 'Freshly baked wholesome brown bread.',
    ),
    CatalogTemplateItem(
      name: 'Parle-G Gold Biscuits',
      priceRupees: 20,
      unit: '130g',
      category: 'Snacks & Biscuits',
      description: 'Crispy golden glucose biscuits with milk goodness.',
    ),
  ];

  static const List<CatalogTemplateItem> medicalSuggestions = [
    CatalogTemplateItem(
      name: 'Dolo 650 Paracetamol Tablets',
      priceRupees: 32,
      unit: '15 tablets',
      category: 'Fever & Pain Relief',
      description: 'Effective relief for headache, body ache and fever.',
    ),
    CatalogTemplateItem(
      name: 'Dettol Antiseptic Disinfectant Liquid',
      priceRupees: 45,
      unit: '100ml',
      category: 'First Aid',
      description: 'Proven antiseptic liquid for wounds and hygiene.',
    ),
    CatalogTemplateItem(
      name: 'Band-Aid Washproof Medicated Strips',
      priceRupees: 30,
      unit: '10 strips',
      category: 'First Aid',
      description: 'Water-resistant adhesive bandages for cuts and grazes.',
    ),
    CatalogTemplateItem(
      name: 'Electral ORS Powder (WHO Formula)',
      priceRupees: 22,
      unit: '21.8g sachet',
      category: 'Wellness & Hydration',
      description: 'Oral rehydration salts for rapid electrolyte restoration.',
    ),
    CatalogTemplateItem(
      name: 'Vicks VapoRub Balm',
      priceRupees: 75,
      unit: '25ml',
      category: 'Cold & Cough',
      description: 'Provides quick relief from nasal congestion and cough.',
    ),
    CatalogTemplateItem(
      name: 'Benadryl Cough Formula Syrup',
      priceRupees: 98,
      unit: '100ml',
      category: 'Cold & Cough',
      description: 'Soothing syrup for dry and allergic cough.',
    ),
    CatalogTemplateItem(
      name: 'Volini Rapid Pain Relief Spray',
      priceRupees: 150,
      unit: '55g',
      category: 'Pain Relief',
      description: 'Fast-acting spray for joint, muscle and neck pain.',
    ),
    CatalogTemplateItem(
      name: 'Himalaya Purifying Neem Face Wash',
      priceRupees: 85,
      unit: '100ml',
      category: 'Personal Care',
      description: 'Herbal cleanser prevents pimples and purifies skin.',
    ),
  ];

  static const List<CatalogTemplateItem> bakerySuggestions = [
    CatalogTemplateItem(
      name: 'Dutch Chocolate Truffle Cake',
      priceRupees: 450,
      unit: '500g',
      category: 'Cakes',
      description: 'Rich dark chocolate ganache with soft sponge layers.',
    ),
    CatalogTemplateItem(
      name: 'Classic Black Forest Cherry Cake',
      priceRupees: 380,
      unit: '500g',
      category: 'Cakes',
      description: 'Whipped vanilla cream, chocolate shavings and sweet cherries.',
    ),
    CatalogTemplateItem(
      name: 'Fresh Pineapple Cream Cake',
      priceRupees: 340,
      unit: '500g',
      category: 'Cakes',
      description: 'Juicy tropical pineapple bits layered in fresh dairy cream.',
    ),
    CatalogTemplateItem(
      name: 'Red Velvet Cream Cheese Cupcake',
      priceRupees: 65,
      unit: '1 piece',
      category: 'Cupcakes',
      description: 'Moist crimson cake crowned with rich cream cheese frosting.',
    ),
    CatalogTemplateItem(
      name: 'Warm Choco Lava Molten Cake',
      priceRupees: 85,
      unit: '1 piece',
      category: 'Desserts',
      description: 'Decadent chocolate cake with a warm flowing fudge center.',
    ),
    CatalogTemplateItem(
      name: 'Freshly Baked Garlic Bread Loaf',
      priceRupees: 70,
      unit: '250g',
      category: 'Artisan Breads',
      description: 'Crusty loaf infused with roasted garlic and fine Italian herbs.',
    ),
    CatalogTemplateItem(
      name: 'Butter Cashew Cookies (Nankhatai)',
      priceRupees: 120,
      unit: '250g box',
      category: 'Cookies & Biscuits',
      description: 'Melt-in-mouth traditional buttery bakery biscuits.',
    ),
  ];

  static const List<CatalogTemplateItem> restaurantSuggestions = [
    CatalogTemplateItem(
      name: 'Hyderabadi Dum Chicken / Veg Biryani',
      priceRupees: 180,
      unit: '1 plate',
      category: 'Rice Bowls',
      description: 'Fragrant basmati rice slow-cooked with aromatic saffron spices.',
    ),
    CatalogTemplateItem(
      name: 'Paneer Butter Masala',
      priceRupees: 210,
      unit: '1 portion',
      category: 'Curries',
      description: 'Fresh cottage cheese cubes simmered in velvety tomato makhani.',
    ),
    CatalogTemplateItem(
      name: 'Butter Garlic Naan',
      priceRupees: 45,
      unit: '1 piece',
      category: 'Breads',
      description: 'Tandoor-baked flatbread glazed with butter and fresh minced garlic.',
    ),
    CatalogTemplateItem(
      name: 'Crispy Masala Dosa with Sambar & Chutney',
      priceRupees: 85,
      unit: '1 plate',
      category: 'South Indian',
      description: 'Golden crepe stuffed with spiced potato mash, served with coconut chutney.',
    ),
    CatalogTemplateItem(
      name: 'Steamed Veg Momos (8 pcs)',
      priceRupees: 90,
      unit: '8 pieces',
      category: 'Appetizers',
      description: 'Thin-wrapper dumplings filled with minced veggies and spicy dip.',
    ),
    CatalogTemplateItem(
      name: 'Masala Cutting Chai',
      priceRupees: 20,
      unit: '1 cup',
      category: 'Beverages',
      description: 'Freshly brewed milk tea infused with crushed ginger and cardamom.',
    ),
  ];

  static const List<CatalogTemplateItem> freshProduceSuggestions = [
    CatalogTemplateItem(
      name: 'Fresh Red Onions (Pyaz)',
      priceRupees: 35,
      unit: '1 kg',
      category: 'Vegetables',
      description: 'Crisp and pungent farm-fresh red onions.',
    ),
    CatalogTemplateItem(
      name: 'Hybrid Juicy Red Tomatoes (Tamatar)',
      priceRupees: 30,
      unit: '1 kg',
      category: 'Vegetables',
      description: 'Firm and ripe tomatoes, great for salads and curries.',
    ),
    CatalogTemplateItem(
      name: 'Fresh Potatoes (Aloo)',
      priceRupees: 28,
      unit: '1 kg',
      category: 'Vegetables',
      description: 'Cleaned earthy potatoes, essential for every Indian kitchen.',
    ),
    CatalogTemplateItem(
      name: 'Robusta Golden Bananas',
      priceRupees: 50,
      unit: '1 dozen',
      category: 'Fruits',
      description: 'Naturally ripened sweet bananas packed with potassium.',
    ),
    CatalogTemplateItem(
      name: 'Kashmiri Royal Delicious Apples',
      priceRupees: 160,
      unit: '1 kg',
      category: 'Fruits',
      description: 'Sweet, crunchy and aromatic high-altitude red apples.',
    ),
  ];

  static const List<CatalogTemplateItem> stationerySuggestions = [
    CatalogTemplateItem(
      name: 'Classmate Spiral Notebook Single Line',
      priceRupees: 85,
      unit: '300 pages',
      category: 'Notebooks',
      description: 'High quality bright ozone-treated paper with durable cover.',
    ),
    CatalogTemplateItem(
      name: 'Reynolds 045 Ball Point Pens (Blue)',
      priceRupees: 50,
      unit: 'Pack of 5',
      category: 'Pens & Writing',
      description: 'Laser tip ball pens for smooth, smudge-free writing.',
    ),
    CatalogTemplateItem(
      name: 'A4 Copier Printing Paper (75 GSM)',
      priceRupees: 320,
      unit: '500 sheets ream',
      category: 'Office & Paper',
      description: 'Super bright white multipurpose printing and copying paper.',
    ),
    CatalogTemplateItem(
      name: 'Fevicol MR Squeezy Glue',
      priceRupees: 25,
      unit: '50g bottle',
      category: 'Adhesives',
      description: 'Strong multipurpose synthetic craft and school adhesive.',
    ),
  ];
}
