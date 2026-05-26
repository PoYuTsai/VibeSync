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
      <main className="flex-1 bg-[#f8f6ff] bg-[radial-gradient(circle_at_top_left,rgba(129,140,248,0.18),transparent_34%),radial-gradient(circle_at_top_right,rgba(232,121,249,0.14),transparent_30%),linear-gradient(180deg,#fbfaff_0%,#f6f3ff_100%)] p-6">
        {children}
      </main>
    </div>
  );
}
