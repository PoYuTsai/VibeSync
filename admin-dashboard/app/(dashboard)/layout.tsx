// app/(dashboard)/layout.tsx
import { Nav } from "@/components/layout/nav";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen">
      <Nav />
      <main className="flex-1 bg-gray-100 dark:bg-gray-950 p-6">
        {children}
      </main>
    </div>
  );
}
