const { Zalo } = require("zca-js");
const { GoogleGenerativeAI } = require("@google/generative-ai");

const required = ["GEMINI_API_KEY", "OWNER_ZALO_ID"];
for (const key of required) {
  if (!process.env[key]) {
    console.error(`❌ Thiếu biến môi trường: ${key}`);
    process.exit(1);
  }
}

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

const zalo = new Zalo();

async function startPyinccZaloBot() {
  const api = await zalo.loginQR();
  console.log("✅ PYINCC Bot Zalo đã sẵn sàng. Chủ tiệm có thể ra lệnh qua Zalo.");

  api.listener.on("message", async (message) => {
    if (message.isSelf) return;
    if (typeof message.data.content !== "string") return;

    const senderId = message.data.uidFrom;
    const text = message.data.content;

    if (senderId !== process.env.OWNER_ZALO_ID) return;

    const prompt = `
Bạn là Trợ lý AI điều hành tiệm thẩm mỹ PYINCC qua Zalo.
Chủ tiệm vừa nhắn: "${text}".
Trả lời ngắn gọn, súc tích bằng tiếng Việt:
- Nếu hỏi báo cáo/lịch hẹn: tóm tắt số liệu hôm nay.
- Nếu yêu cầu đổi ca trực hoặc duyệt giá ca khó: xác nhận đã ghi nhận.
`;

    try {
      const result = await model.generateContent(prompt);
      await api.sendMessage(result.response.text(), message.threadId, message.type);
    } catch (err) {
      console.error("Lỗi gọi Gemini:", err.message);
    }
  });

  api.listener.start();
}

startPyinccZaloBot().catch((err) => {
  console.error("Lỗi khởi động bot:", err);
  process.exit(1);
});
