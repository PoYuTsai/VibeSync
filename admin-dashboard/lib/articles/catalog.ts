export type ManagedArticleStatus =
  | "draft"
  | "pending_review"
  | "published_in_app"
  | "archived";

export type ArticleSourceFormat = "markdown" | "plain_text";

export interface AppArticleCatalogItem {
  id: string;
  title: string;
  subtitle: string;
  category: string;
  readTime: string;
  source: string;
  tags: string[];
  status: "published_in_app";
}

const baseAppArticles = [
  {
    id: "1",
    title: "如何和陌生人開始對話",
    subtitle: "破冰不靠罐頭問題，3 步驟讓對話自然展開",
    category: "核心社交心法",
    readTime: "8 分鐘",
    source: "The Art of Manliness",
  },
  {
    id: "2",
    title: "深度對話的藝術",
    subtitle: "從「你好嗎」到真正的交流，5 個讓對話有深度的技巧",
    category: "深度交流",
    readTime: "6 分鐘",
    source: "Psychology Today",
  },
  {
    id: "3",
    title: "如何變得更幽默",
    subtitle: "10 個提升幽默感的實用技巧，讓她笑著想回你",
    category: "幽默與調情",
    readTime: "7 分鐘",
    source: "Practical Psychology",
  },
  {
    id: "4",
    title: "自信不是裝出來的",
    subtitle: "真正的自信來自接受不完美的自己",
    category: "核心社交心法",
    readTime: "7 分鐘",
    source: "Mark Manson",
  },
  {
    id: "5",
    title: "魅力的三大支柱",
    subtitle: "溫暖、力量、存在感，缺一不可",
    category: "核心社交心法",
    readTime: "7 分鐘",
    source: "Charisma on Command",
  },
  {
    id: "6",
    title: "好的對話者都做了什麼",
    subtitle: "不是能說，而是能讓對方想說",
    category: "核心社交心法",
    readTime: "6 分鐘",
    source: "The School of Life",
  },
  {
    id: "7",
    title: "話少不是問題，不會開口才是",
    subtitle: "內向者也能自在聊天的 7 個方法",
    category: "核心社交心法",
    readTime: "7 分鐘",
    source: "SocialSelf",
  },
  {
    id: "8",
    title: "情緒智商決定你的魅力值",
    subtitle: "7 個提升 EQ 的日常練習",
    category: "深度交流",
    readTime: "7 分鐘",
    source: "Success.com",
  },
  {
    id: "9",
    title: "脆弱是最強的武器",
    subtitle: "為什麼敢示弱的人更有吸引力",
    category: "深度交流",
    readTime: "6 分鐘",
    source: "MindBodyGreen",
  },
  {
    id: "10",
    title: "讓人放鬆的 11 個小細節",
    subtitle: "她在你身邊自在，才會想靠近",
    category: "深度交流",
    readTime: "7 分鐘",
    source: "Bustle",
  },
  {
    id: "11",
    title: "主動傾聽：被低估的超能力",
    subtitle: "聽懂她沒說出口的話",
    category: "深度交流",
    readTime: "6 分鐘",
    source: "The Good Men Project",
  },
  {
    id: "12",
    title: "訊息調情的潛規則",
    subtitle: "回覆時機、語氣、長度都是學問",
    category: "幽默與調情",
    readTime: "7 分鐘",
    source: "AskMen",
  },
  {
    id: "13",
    title: "調情不是騷擾：分寸指南",
    subtitle: "讓她覺得被欣賞，而不是被冒犯",
    category: "幽默與調情",
    readTime: "7 分鐘",
    source: "",
  },
  {
    id: "14",
    title: "會說故事的人最迷人",
    subtitle: "把日常小事講成精彩故事的框架",
    category: "幽默與調情",
    readTime: "7 分鐘",
    source: "Real Men Real Style",
  },
  {
    id: "15",
    title: "肢體語言比你說的話更大聲",
    subtitle: "15 個讓你更有魅力的身體訊號",
    category: "非語言溝通",
    readTime: "8 分鐘",
    source: "Science of People",
  },
  {
    id: "16",
    title: "眼神接觸的力量",
    subtitle: "看太多像盯人，看太少像心虛",
    category: "非語言溝通",
    readTime: "6 分鐘",
    source: "Healthline",
  },
  {
    id: "17",
    title: "你的聲音透露了一切",
    subtitle: "語速、音調、停頓，都在傳遞訊息",
    category: "非語言溝通",
    readTime: "6 分鐘",
    source: "The Art of Manliness",
  },
  {
    id: "18",
    title: "社交技巧是可以練的",
    subtitle: "從觀察到實踐的完整指南",
    category: "非語言溝通",
    readTime: "7 分鐘",
    source: "Verywell Mind",
  },
  {
    id: "19",
    title: "一句好的稱讚勝過千句話",
    subtitle: "讓人記住的稱讚都有這個特點",
    category: "核心社交心法",
    readTime: "6 分鐘",
    source: "Lifehack",
  },
  {
    id: "20",
    title: "幽默背後的心理學",
    subtitle: "為什麼好笑的人更受歡迎",
    category: "幽默與調情",
    readTime: "7 分鐘",
    source: "Practical Psychology",
  },
  {
    id: "21",
    title: "低壓邀約：讓對方容易說 yes，也能舒服說 no",
    subtitle: "把邀約說清楚，但不把壓力丟給對方",
    category: "核心社交心法",
    readTime: "6 分鐘",
    source: "DatingNetwork + Science of People",
  },
  {
    id: "22",
    title: "留白不是冷處理：不要一直追問，讓節奏回來",
    subtitle: "當你開始焦慮想補很多訊息，先把自己穩住",
    category: "核心社交心法",
    readTime: "6 分鐘",
    source: "VibeSync Original",
  },
  {
    id: "23",
    title: "性張力不是黃腔：把挑逗接成有來有往",
    subtitle: "從單向觀察，拉成雙方都能參與的曖昧互動",
    category: "幽默與調情",
    readTime: "6 分鐘",
    source: "新世界 TV × 良叔 / VibeSync 改寫",
  },
  {
    id: "24",
    title: "破解兩性吸引力密碼：權力意識與框架控制",
    subtitle: "不是控制對方，而是穩住自己、守住界線、帶出有方向的互動",
    category: "核心社交心法",
    readTime: "7 分鐘",
    source: "VibeSync Original / 桌面稿件改寫",
  },
] as const;

function practiceTagFor(id: string, category: string) {
  if (["1", "7"].includes(id)) return "開話題";
  if (["2", "8", "9", "10", "11", "14"].includes(id)) return "延伸與共鳴";
  if (id === "21") return "推進與邀約";
  if (["13", "22", "24"].includes(id)) return "判斷與邊界";
  if (category === "幽默與調情") return "性張力與曖昧";
  if (category === "深度交流") return "延伸與共鳴";
  if (category === "非語言溝通") return "穩住自己";
  return "穩住自己";
}

export const appPublishedArticles: AppArticleCatalogItem[] = baseAppArticles.map(
  (article) => ({
    ...article,
    status: "published_in_app",
    tags: ["App 已上架", article.category, practiceTagFor(article.id, article.category)],
  })
);

export const defaultArticleCategories = Array.from(
  new Set(appPublishedArticles.map((article) => article.category))
).sort((a, b) => a.localeCompare(b, "zh-Hant"));
