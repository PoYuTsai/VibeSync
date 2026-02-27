// app/403/page.tsx
import Link from "next/link";
import { Button } from "@/components/ui/button";

export default function ForbiddenPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-100 dark:bg-gray-900">
      <div className="text-center">
        <h1 className="text-6xl font-bold text-gray-800 dark:text-gray-200 mb-4">
          403
        </h1>
        <h2 className="text-2xl font-semibold text-gray-600 dark:text-gray-400 mb-4">
          Access Denied
        </h2>
        <p className="text-gray-500 dark:text-gray-500 mb-8">
          您沒有權限存取 Admin Dashboard。
          <br />
          如需存取權限，請聯繫系統管理員。
        </p>
        <Link href="/login">
          <Button variant="outline">返回登入</Button>
        </Link>
      </div>
    </div>
  );
}
