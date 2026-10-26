/** Goods and services, as the web app uses them. The server sends money and counts as text or numbers; these are always numbers. */
export interface PriceOption {
  label: string;
  price: number;
}

export interface Product {
  id: number;
  name: string;
  sku: string;
  barcode: string | null;
  description: string | null;
  category_id: number | null;
  category_name: string | null;
  brand_id: number | null;
  brand_name: string | null;
  unit: string;
  quantity: number;
  min_stock: number;
  cost_price: number;
  selling_price: number;
  tax_percent: number | null;
  status: 'active' | 'inactive';
  is_service: boolean;
  duration_minutes: number | null;
  rebook_after_weeks: number | null;
  commission_percent: number | null;
  commission_fixed: number | null;
  package_sessions: number | null;
  package_service_id: number | null;
  package_valid_days: number | null;
  /** Account ids of the staff who may do this service; empty = anyone. */
  staff_ids: string[];
  price_options: PriceOption[];
}

export interface ProductFilters {
  q: string;
  status: '' | 'active' | 'inactive';
  kind: '' | 'goods' | 'services';
  lowStock: boolean;
  categoryId: number | null;
  page: number;
}

export interface ProductPage {
  items: Product[];
  page: number;
  lastPage: number;
  total: number;
}

/** What is sent when a product or service is saved. Fields the person may not set are left out. */
export interface ProductBody {
  name: string;
  description: string | null;
  sku?: string;
  barcode: string | null;
  category_id: number | null;
  brand_id: number | null;
  unit: string;
  cost_price: number;
  selling_price: number;
  quantity: number;
  min_stock: number;
  status: 'active' | 'inactive';
  tax_percent: number | null;
  is_service: boolean;
  duration_minutes: number | null;
  rebook_after_weeks: number | null;
  commission_percent: number | null;
  commission_fixed: number | null;
  package_sessions: number | null;
  package_service_id: number | null;
  package_valid_days: number | null;
  staff_ids: string[];
  price_options: PriceOption[];
}

/** A category or a brand: the same two fields, the same screens. */
export interface Named {
  id: number;
  name: string;
  description: string | null;
  status: 'active' | 'inactive';
  products_count: number;
}

export type NamedKind = 'categories' | 'brands';

/** A member of the business's staff, for "done by". */
export interface StaffMember {
  id: string;
  name: string;
  role: string;
}

/** One kind of goods a service uses up each time it is done. */
export interface ServiceMaterial {
  material_product_id: number;
  name: string;
  quantity: number;
  in_stock: number;
}
