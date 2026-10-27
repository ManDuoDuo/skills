export interface Health {
  status: string;
  database: string;
  version: string;
}

export async function fetchHealth(): Promise<Health> {
  const response = await fetch("/health");
  if (!response.ok) throw new Error(`health check failed: ${response.status}`);
  return response.json() as Promise<Health>;
}
