"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

interface UserRow {
  id: string;
  email: string;
  created_at: string;
  subscription_tier: string;
}

interface UsersResponse {
  rows: UserRow[];
  stats: {
    total: number;
    thisMonth: number;
    thisWeek: number;
  };
}

export default function UsersPage() {
  const [users, setUsers] = useState<UserRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({
    total: 0,
    thisMonth: 0,
    thisWeek: 0,
  });

  useEffect(() => {
    async function fetchUsers() {
      try {
        const response = await fetch("/api/admin/users", { cache: "no-store" });
        if (!response.ok) {
          throw new Error("Failed to load users");
        }

        const payload = (await response.json()) as UsersResponse;
        setUsers(payload.rows ?? []);
        setStats(payload.stats ?? { total: 0, thisMonth: 0, thisWeek: 0 });
      } catch (error) {
        console.error("Failed to fetch users:", error);
      } finally {
        setLoading(false);
      }
    }

    void fetchUsers();
  }, []);

  const formatDate = (value: string) =>
    new Date(value).toLocaleDateString("en-US", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });

  const getTierBadge = (tier: string) => {
    const colors: Record<string, string> = {
      free: "bg-gray-100 text-gray-800",
      starter: "bg-blue-100 text-blue-800",
      essential: "bg-purple-100 text-purple-800",
    };

    return (
      <span
        className={`rounded-full px-2 py-1 text-xs font-medium ${colors[tier] ?? colors.free}`}
      >
        {tier.charAt(0).toUpperCase() + tier.slice(1)}
      </span>
    );
  };

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Users</h1>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Total users
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.total}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              This month
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.thisMonth}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Last 7 days
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.thisWeek}</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Recent users</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="animate-pulse space-y-2">
              {[1, 2, 3, 4, 5].map((row) => (
                <div key={row} className="h-10 rounded bg-gray-100" />
              ))}
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Email</TableHead>
                  <TableHead>Tier</TableHead>
                  <TableHead>Created</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {users.map((user) => (
                  <TableRow key={user.id}>
                    <TableCell className="font-medium">{user.email}</TableCell>
                    <TableCell>{getTierBadge(user.subscription_tier)}</TableCell>
                    <TableCell>{formatDate(user.created_at)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
