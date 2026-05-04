from social_agents.platforms.base import Platform


class Instagram(Platform):
    name = "instagram"
    login_url = "https://www.instagram.com/accounts/login/"

    def post_goal(self, *, media: str, caption: str) -> str:
        return (
            "You are at instagram.com, already logged in.\n"
            "Goal: publish a new feed post with the provided image and caption.\n"
            "\n"
            "Plan:\n"
            "1. Click the 'Create' button (a + or compose icon, usually in the left sidebar or top nav).\n"
            "2. In the upload dialog, click 'Select from computer'.\n"
            f"3. Upload this exact local file path: {media}\n"
            "4. Click 'Next'. If a crop step appears, click 'Next' again. If a filter / edit step appears, click 'Next' again.\n"
            "5. Paste this caption verbatim into the caption textarea, including any emoji and line breaks:\n"
            "---\n"
            f"{caption}\n"
            "---\n"
            "6. Click 'Share'.\n"
            "7. Wait for the share dialog to close. Verify the post appears at the top of the user's profile grid.\n"
            "\n"
            "If you encounter a 'Save your login info?' or notifications dialog at any point, dismiss it ('Not now') and continue.\n"
            "Do not navigate away from instagram.com. Do not edit the image.\n"
        )
