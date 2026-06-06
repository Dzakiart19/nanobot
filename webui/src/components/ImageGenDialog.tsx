import { useCallback, useRef, useState } from "react";
import { ImageIcon, Loader2, Sparkles } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { generateImage } from "@/lib/api";
import { cn } from "@/lib/utils";

interface ImageGenDialogProps {
  open: boolean;
  token: string;
  onOpenChange: (open: boolean) => void;
  onSuccess: (images: string[], prompt: string) => void;
}

export function ImageGenDialog({
  open,
  token,
  onOpenChange,
  onSuccess,
}: ImageGenDialogProps) {
  const [prompt, setPrompt] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const handleGenerate = useCallback(async () => {
    const trimmed = prompt.trim();
    if (!trimmed || loading) return;
    setLoading(true);
    setError(null);
    try {
      const result = await generateImage(token, trimmed);
      if (!result.images || result.images.length === 0) {
        setError("No images returned. The image generation endpoint may not be available.");
        return;
      }
      onSuccess(result.images, trimmed);
      setPrompt("");
      onOpenChange(false);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message || "Image generation failed.");
    } finally {
      setLoading(false);
    }
  }, [loading, onOpenChange, onSuccess, prompt, token]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        void handleGenerate();
      }
    },
    [handleGenerate],
  );

  return (
    <Dialog open={open} onOpenChange={(next) => {
      if (!loading) onOpenChange(next);
    }}>
      <DialogContent className="max-w-md rounded-[22px] border-border/70 bg-popover p-5 shadow-2xl">
        <DialogHeader className="text-left">
          <DialogTitle className="flex items-center gap-2">
            <ImageIcon className="h-4 w-4 text-muted-foreground" aria-hidden />
            Generate Image
          </DialogTitle>
          <DialogDescription>
            Describe the image you want to generate. Press Ctrl+Enter to generate.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          <textarea
            ref={textareaRef}
            value={prompt}
            onChange={(e) => {
              setPrompt(e.target.value);
              setError(null);
            }}
            onKeyDown={handleKeyDown}
            placeholder="A futuristic cityscape at sunset, digital art…"
            rows={4}
            disabled={loading}
            autoFocus
            className={cn(
              "w-full resize-none rounded-xl border border-input bg-background px-3 py-2.5",
              "text-sm text-foreground placeholder:text-muted-foreground/60",
              "focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-0",
              "disabled:cursor-not-allowed disabled:opacity-60",
              "transition-colors",
            )}
          />
          {error ? (
            <p
              role="alert"
              className="rounded-lg border border-destructive/40 bg-destructive/8 px-3 py-2 text-[12px] text-destructive"
            >
              {error}
            </p>
          ) : null}
        </div>
        <DialogFooter className="gap-2 sm:space-x-0">
          <Button
            type="button"
            variant="outline"
            disabled={loading}
            onClick={() => onOpenChange(false)}
          >
            Cancel
          </Button>
          <Button
            type="button"
            disabled={!prompt.trim() || loading}
            onClick={() => void handleGenerate()}
            className="gap-1.5"
          >
            {loading ? (
              <>
                <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden />
                Generating…
              </>
            ) : (
              <>
                <Sparkles className="h-3.5 w-3.5" aria-hidden />
                Generate
              </>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
