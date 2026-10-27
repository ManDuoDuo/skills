import { useEffect, useState } from "react";
import { fetchHealth, type Health } from "./api/health";

export default function App() {
  const [health, setHealth] = useState<Health | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    let active = true;
    fetchHealth()
      .then((result) => {
        if (active) setHealth(result);
      })
      .catch(() => {
        if (active) setError(true);
      });
    return () => {
      active = false;
    };
  }, []);

  return (
    <main>
      <p className="eyebrow">PROJECT VAULT</p>
      <h1>项目健康状态</h1>
      <section aria-live="polite">
        {health ? (
          <>
            <strong>服务正常</strong>
            <dl>
              <div><dt>应用</dt><dd>{health.status}</dd></div>
              <div><dt>数据库</dt><dd>{health.database}</dd></div>
              <div><dt>版本</dt><dd>{health.version}</dd></div>
            </dl>
          </>
        ) : (
          <strong>{error ? "暂时无法连接后端" : "正在检查…"}</strong>
        )}
      </section>
    </main>
  );
}
