import { test, expect } from '@playwright/test';

test('We can log in on the admin and view the dashboard', async ({ page }) => {
  await page.goto('/admin/');

  await page.getByRole('textbox', { name: 'Username *' }).fill('exampleuser');
  await page.getByRole('textbox', { name: 'Password *' }).fill('examplepassword123');

  await page.getByRole('button', { name: 'Sign in' }).click();

  await page.waitForURL('admin/admin/dashboard/**');

  await expect(page.getByText('Thank you for choosing Mage-OS.')).toBeVisible();
});
