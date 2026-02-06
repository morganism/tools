import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/**
 * Async operation handler using Service Worker
 * Prevents blocking the main thread for heavy operations
 */
export async function performAsyncOperation(payload: any): Promise<any> {
  if ('serviceWorker' in navigator && navigator.serviceWorker.controller) {
    return new Promise((resolve, reject) => {
      const messageChannel = new MessageChannel();
      
      messageChannel.port1.onmessage = (event) => {
        if (event.data.success) {
          resolve(event.data.result);
        } else {
          reject(new Error(event.data.error));
        }
      };
      
      navigator.serviceWorker.controller!.postMessage(
        {
          type: 'ASYNC_OPERATION',
          payload,
        },
        [messageChannel.port2]
      );
    });
  } else {
    // Fallback if service worker not available
    return Promise.resolve({ processed: true, data: payload });
  }
}

/**
 * Debounce function for performance optimization
 */
export function debounce<T extends (...args: any[]) => any>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: NodeJS.Timeout | null = null;
  
  return function executedFunction(...args: Parameters<T>) {
    const later = () => {
      timeout = null;
      func(...args);
    };
    
    if (timeout) clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

/**
 * Throttle function for scroll/resize events
 */
export function throttle<T extends (...args: any[]) => any>(
  func: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle: boolean;
  
  return function executedFunction(...args: Parameters<T>) {
    if (!inThrottle) {
      func(...args);
      inThrottle = true;
      setTimeout(() => (inThrottle = false), limit);
    }
  };
}

/**
 * Animate element with bounce effect
 */
export function animateWithBounce(element: HTMLElement, delay: number = 0) {
  setTimeout(() => {
    element.style.animation = 'bounceIn 0.6s cubic-bezier(0.68, -0.55, 0.265, 1.55)';
  }, delay);
}

/**
 * Fade in element with upward motion
 */
export function fadeInUp(element: HTMLElement, delay: number = 0) {
  setTimeout(() => {
    element.style.animation = 'fadeInUp 0.6s cubic-bezier(0.16, 1, 0.3, 1) forwards';
  }, delay);
}

/**
 * Check if element is in viewport
 */
export function isInViewport(element: HTMLElement): boolean {
  const rect = element.getBoundingClientRect();
  return (
    rect.top >= 0 &&
    rect.left >= 0 &&
    rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) &&
    rect.right <= (window.innerWidth || document.documentElement.clientWidth)
  );
}

/**
 * Smooth scroll to element
 */
export function smoothScrollTo(elementId: string) {
  const element = document.getElementById(elementId);
  if (element) {
    element.scrollIntoView({
      behavior: 'smooth',
      block: 'start',
    });
  }
}

/**
 * Generate random color from Apple palette
 */
export function getRandomAppleColor(): string {
  const colors = [
    '#007AFF', // Apple Blue
    '#5AC8FA', // Light Blue
    '#34C759', // Green
    '#FF9500', // Orange
    '#FF3B30', // Red
    '#AF52DE', // Purple
  ];
  return colors[Math.floor(Math.random() * colors.length)];
}

/**
 * Format date in Apple style
 */
export function formatAppleDate(date: Date): string {
  const options: Intl.DateTimeFormatOptions = {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  };
  return date.toLocaleDateString('en-US', options);
}
